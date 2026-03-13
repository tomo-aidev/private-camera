import SwiftUI
import AVFoundation
import os.log

/// Auto-record view — starts recording immediately when shown.
/// Uses a dedicated AVCaptureSession with sequential async setup for reliable auto-start.
struct AutoRecordView: View {
    /// When true, navigate to PasscodeView → BOX after saving. When false, just dismiss.
    var navigateToBoxAfterSave: Bool = true

    @StateObject private var vm = AutoRecordVM()
    @Environment(\.dismiss) private var dismiss
    @State private var navigateToBox = false

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(session: vm.session)
                .ignoresSafeArea()

            VStack {
                Spacer()

                // Recording indicator
                if vm.isRecording {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text(vm.formattedDuration)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.red.opacity(0.3))
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 16)
                }

                // Stop button (recording) / Close button (not recording)
                Button {
                    AppTheme.mediumImpact()
                    if vm.isRecording {
                        vm.stopRecording()
                    } else {
                        dismiss()
                    }
                } label: {
                    ShutterButton(
                        mode: .video,
                        isRecording: vm.isRecording,
                        onTap: {
                            AppTheme.mediumImpact()
                            if vm.isRecording {
                                vm.stopRecording()
                            } else {
                                dismiss()
                            }
                        }
                    )
                }

                // Home indicator spacer
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 128, height: 4)
                    .padding(.top, 32)
                    .padding(.bottom, 8)
            }
            .padding(.bottom, 8)
        }
        .background(.black)
        .statusBarHidden()
        .task {
            await vm.runAutoRecord()
        }
        .onDisappear {
            vm.teardown()
        }
        .onChange(of: vm.didFinishSaving) { _, finished in
            if finished {
                vm.didFinishSaving = false
                if navigateToBoxAfterSave {
                    navigateToBox = true
                } else {
                    // Already in BOX context — just dismiss
                    dismiss()
                }
            }
        }
        .fullScreenCover(isPresented: $navigateToBox) {
            PasscodeView()
                .onDisappear {
                    dismiss()
                }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class AutoRecordVM: NSObject, ObservableObject {

    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var didFinishSaving = false

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.privatecamera.autorecord", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.privatecamera", category: "AutoRecord")
    private var movieOutput: AVCaptureMovieFileOutput?
    private var recordingTimer: Timer?

    var formattedDuration: String {
        let h = Int(recordingDuration) / 3600
        let m = Int(recordingDuration) / 60 % 60
        let s = Int(recordingDuration) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Main Flow (sequential async — each step waits for completion)

    func runAutoRecord() async {
        logger.info("Auto-record: starting")

        // 1. Check video permission
        let videoStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if videoStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { logger.error("Auto-record: video denied"); return }
        } else if videoStatus != .authorized {
            logger.error("Auto-record: video not authorized")
            return
        }

        // 2. Check audio permission
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if audioStatus == .notDetermined {
            await AVCaptureDevice.requestAccess(for: .audio)
        }

        // 3. Configure and start session (wait for completion)
        let success = await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else { continuation.resume(returning: false); return }
                let ok = self.configureAndStartSession()
                continuation.resume(returning: ok)
            }
        }

        guard success else {
            logger.error("Auto-record: session config failed")
            return
        }

        // 4. Start recording (wait for dispatch to sessionQueue)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self,
                      let movieOut = self.movieOutput,
                      self.session.isRunning,
                      movieOut.connection(with: .video) != nil else {
                    self?.logger.error("Auto-record: preconditions not met for recording")
                    continuation.resume()
                    return
                }

                let tempURL = self.makeTempURL()
                self.logger.info("Auto-record: calling startRecording")
                movieOut.startRecording(to: tempURL, recordingDelegate: self)
                self.logger.info("Auto-record: startRecording returned, isRecording=\(movieOut.isRecording)")
                continuation.resume()
            }
        }
    }

    // MARK: - Session Configuration

    private func configureAndStartSession() -> Bool {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        guard let camera = discovery.devices.first else {
            logger.error("No camera found")
            return false
        }

        session.beginConfiguration()
        session.sessionPreset = .high

        // Video input
        do {
            let videoIn = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(videoIn) else {
                session.commitConfiguration()
                return false
            }
            session.addInput(videoIn)
        } catch {
            logger.error("Video input failed: \(error)")
            session.commitConfiguration()
            return false
        }

        // Audio input (optional — continue without if it fails)
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            if let audioIn = try? AVCaptureDeviceInput(device: audioDevice),
               session.canAddInput(audioIn) {
                session.addInput(audioIn)
            }
        }

        // Movie output
        let movieOut = AVCaptureMovieFileOutput()
        guard session.canAddOutput(movieOut) else {
            session.commitConfiguration()
            return false
        }
        session.addOutput(movieOut)
        movieOutput = movieOut

        if let conn = movieOut.connection(with: .video) {
            conn.videoRotationAngle = 90
            if conn.isVideoStabilizationSupported {
                conn.preferredVideoStabilizationMode = .auto
            }
        }

        session.commitConfiguration()

        // Start session (synchronous — blocks until running)
        session.startRunning()
        logger.info("Auto-record: session started, isRunning=\(self.session.isRunning)")

        return session.isRunning
    }

    // MARK: - Recording Control

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self, let movieOut = self.movieOutput, movieOut.isRecording else { return }
            movieOut.stopRecording()
        }
    }

    func teardown() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if let movieOut = self.movieOutput, movieOut.isRecording {
                movieOut.stopRecording()
            }
            self.session.stopRunning()
        }
    }

    private func makeTempURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let tempDir = appSupport.appendingPathComponent("PrivateBox/temp", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension AutoRecordVM: AVCaptureFileOutputRecordingDelegate {

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        Task { @MainActor in
            self.logger.info("Recording started")
            self.isRecording = true
            self.recordingDuration = 0
            self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.recordingDuration += 1.0 }
            }
        }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let url = outputFileURL
        let recordingError = error
        Task { @MainActor in
            self.isRecording = false
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil

            if let recordingError {
                let nsErr = recordingError as NSError
                if nsErr.domain == AVFoundationErrorDomain && nsErr.code == -11806 {
                    self.logger.info("Recording stopped by user")
                } else {
                    self.logger.error("Recording failed: \(recordingError.localizedDescription)")
                    try? FileManager.default.removeItem(at: url)
                    return
                }
            }

            // Save to PrivateBox
            let saved = SecureStorage.shared.saveVideoFile(from: url)
            if let fileId = saved {
                self.logger.info("Video saved: \(fileId)")
                self.didFinishSaving = true
            } else {
                self.logger.error("Save failed")
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
