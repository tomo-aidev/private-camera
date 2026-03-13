import SwiftUI
import AVFoundation
import os.log

/// Full-screen video recording view with independent AVCaptureSession.
/// Layout matches CameraView (no timer). Uses `.high` preset for reliable recording.
struct VideoRecordingView: View {
    let autoStart: Bool
    @StateObject private var vm = VideoRecordingVM()
    @Environment(\.dismiss) private var dismiss
    @State private var initialPinchZoom: CGFloat = 1.0
    @State private var showSettings = false
    @State private var navigateToBox = false
    @State private var videoMode: CameraMode = .video

    init(autoStart: Bool = false) {
        self.autoStart = autoStart
    }

    var body: some View {
        ZStack {
            // MARK: - Viewfinder
            CameraPreviewView(session: vm.session)
                .ignoresSafeArea()
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            AppTheme.lightImpact()
                            vm.focus(at: value.location, in: UIScreen.main.bounds.size)
                        }
                )
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            vm.handlePinchZoom(scale: value.magnification, initialZoom: initialPinchZoom)
                        }
                        .onEnded { _ in
                            initialPinchZoom = vm.currentZoomFactor
                        }
                )

            // Focus ring
            if let focusPoint = vm.focusPoint {
                FocusRingView(position: focusPoint)
            }

            // MARK: - UI Layers
            VStack {
                header
                Spacer()

                // Recording time (above footer when recording)
                if vm.isRecording {
                    recordingTimeView
                }

                footer
            }
        }
        .background(.black)
        .statusBarHidden()
        .task {
            await vm.setup()
            initialPinchZoom = vm.currentZoomFactor

            // Auto-start: "press" the record button after session is ready
            if autoStart && !vm.isRecording {
                vm.startRecording()
            }
        }
        .onDisappear {
            vm.teardown()
        }
        .onChange(of: vm.didFinishSaving) { _, finished in
            if finished {
                vm.didFinishSaving = false
                navigateToBox = true
            }
        }
        .fullScreenCover(isPresented: $navigateToBox) {
            PasscodeView()
                .onDisappear {
                    // Returning from BOX → dismiss video view → back to camera
                    dismiss()
                }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            // Flash toggle
            Button {
                AppTheme.lightImpact()
                vm.toggleFlash()
            } label: {
                Image(systemName: vm.isFlashEnabled ? "bolt.fill" : "bolt.slash")
                    .font(.system(size: 18))
                    .foregroundColor(vm.isFlashEnabled ? AppTheme.primary : .white.opacity(0.8))
                    .frame(width: 44, height: 44)
            }

            Spacer()

            // Settings
            Button {
                AppTheme.lightImpact()
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.3), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)
            .ignoresSafeArea()
        )
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            // Zoom control
            if !vm.zoomThresholds.isEmpty {
                ZoomArcView(
                    thresholds: vm.zoomThresholds,
                    currentZoom: $vm.currentZoomFactor,
                    displayDivisor: vm.zoomDisplayDivisor,
                    onZoomSelected: { factor in
                        vm.setZoom(factor)
                    }
                )
                .padding(.bottom, 16)
            }

            // Mode switcher — selecting 写真 returns to camera
            ModeSwitcherView(
                currentMode: $videoMode,
                onModeChange: { mode in
                    if mode == .photo {
                        if vm.isRecording {
                            vm.stopRecording()
                        }
                        dismiss()
                    }
                }
            )
            .padding(.bottom, 32)

            // Main interaction bar
            HStack {
                // Private Box button
                Button {
                    AppTheme.lightImpact()
                    navigateToBox = true
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            .background(Circle().fill(Color.white.opacity(0.05)))
                            .frame(width: 48, height: 48)

                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                Spacer()

                // Shutter button
                ShutterButton(
                    mode: .video,
                    isRecording: vm.isRecording,
                    onTap: {
                        if vm.isRecording {
                            vm.stopRecording()
                        } else {
                            vm.startRecording()
                        }
                    }
                )

                Spacer()

                // Camera flip button (placeholder — video uses back camera only)
                Button {
                    AppTheme.mediumImpact()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            .background(Circle().fill(Color.white.opacity(0.05)))
                            .frame(width: 48, height: 48)

                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 40)

            // Home indicator spacer
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.2))
                .frame(width: 128, height: 4)
                .padding(.top, 32)
                .padding(.bottom, 8)
        }
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Recording Time

    private var recordingTimeView: some View {
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
        .padding(.bottom, 8)
    }
}

// MARK: - ViewModel

@MainActor
final class VideoRecordingVM: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var zoomThresholds: [(label: String, factor: CGFloat)] = []
    @Published var zoomDisplayDivisor: CGFloat = 1.0
    @Published var isFlashEnabled = false
    @Published var focusPoint: CGPoint? = nil
    @Published var didFinishSaving = false

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.privatecamera.videorecording", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.privatecamera", category: "VideoRecording")

    private var currentDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
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

    // MARK: - Setup

    func setup() async {
        // Check video permission
        let videoStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if videoStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { return }
        } else if videoStatus != .authorized {
            return
        }

        // Check audio permission
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if audioStatus == .notDetermined {
            await AVCaptureDevice.requestAccess(for: .audio)
        }

        // Wait for session to fully configure and start running
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                self?.configureSession()
                continuation.resume()
            }
        }
    }

    private func configureSession() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )

        guard let camera = discoverySession.devices.first else {
            logger.error("No camera device found")
            return
        }

        let settings = PrivacySettingsManager.shared

        session.beginConfiguration()

        // Use .high preset — reliable recording on all devices
        session.sessionPreset = .high

        // Add video input
        do {
            let videoIn = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(videoIn) {
                session.addInput(videoIn)
                videoInput = videoIn
                currentDevice = camera
            }
        } catch {
            logger.error("Failed to create video input: \(error)")
        }

        // Add audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            do {
                let audioIn = try AVCaptureDeviceInput(device: audioDevice)
                if session.canAddInput(audioIn) {
                    session.addInput(audioIn)
                    audioInput = audioIn
                }
            } catch {
                logger.error("Failed to create audio input: \(error)")
            }
        }

        // Add movie output
        let movieOut = AVCaptureMovieFileOutput()
        movieOut.maxRecordedDuration = CMTime(seconds: 3600, preferredTimescale: 600)
        if session.canAddOutput(movieOut) {
            session.addOutput(movieOut)
            movieOutput = movieOut

            if let connection = movieOut.connection(with: .video) {
                connection.videoRotationAngle = 90
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
        }

        session.commitConfiguration()

        // Apply frame rate from settings (works on top of .high preset)
        let targetFPS = Double(settings.videoFrameRate.rawValue)
        do {
            try camera.lockForConfiguration()
            let maxFPS = camera.activeFormat.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30
            let fps = min(targetFPS, maxFPS)
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            camera.unlockForConfiguration()
            logger.info("Applied frame rate: \(Int(fps))fps")
        } catch {
            logger.error("Failed to apply frame rate: \(error)")
        }

        // Build zoom thresholds
        let switchOvers = camera.virtualDeviceSwitchOverVideoZoomFactors
        let hasUltraWide = camera.deviceType == .builtInTripleCamera || camera.deviceType == .builtInDualWideCamera
        var thresholds: [(label: String, factor: CGFloat)] = []
        var divisor: CGFloat = 1.0

        if hasUltraWide && !switchOvers.isEmpty {
            divisor = CGFloat(truncating: switchOvers[0])
            thresholds.append((label: "0.5x", factor: 1.0))
            thresholds.append((label: "1x", factor: divisor))

            let twoXRaw = divisor * 2.0
            if twoXRaw <= camera.maxAvailableVideoZoomFactor {
                thresholds.append((label: "2x", factor: twoXRaw))
            }

            if switchOvers.count > 1 {
                let teleFactor = CGFloat(truncating: switchOvers[1])
                let displayValue = teleFactor / divisor
                let label = displayValue == floor(displayValue)
                    ? String(format: "%.0fx", displayValue)
                    : String(format: "%.1fx", displayValue)
                thresholds.append((label: label, factor: teleFactor))
            }
        } else {
            thresholds.append((label: "1x", factor: 1.0))
            if camera.maxAvailableVideoZoomFactor >= 2.0 {
                thresholds.append((label: "2x", factor: 2.0))
            }
        }

        // Set initial zoom to "1x" (wide lens)
        let initialZoom: CGFloat
        if let firstSwitch = switchOvers.first {
            initialZoom = CGFloat(truncating: firstSwitch)
        } else {
            initialZoom = 1.0
        }

        do {
            try camera.lockForConfiguration()
            camera.videoZoomFactor = initialZoom
            camera.unlockForConfiguration()
        } catch {
            logger.error("Failed to set initial zoom: \(error)")
        }

        Task { @MainActor in
            self.zoomThresholds = thresholds
            self.zoomDisplayDivisor = divisor
            self.currentZoomFactor = initialZoom
        }

        // Start session (synchronous — blocks until session is running)
        session.startRunning()
        logger.info("Video session started: isRunning=\(self.session.isRunning)")
    }

    // MARK: - Recording

    func startRecording() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let movieOut = self.movieOutput else {
                self.logger.error("movieOutput is nil")
                return
            }
            guard self.session.isRunning else {
                self.logger.error("session is not running")
                return
            }
            guard movieOut.connection(with: .video) != nil else {
                self.logger.error("No video connection")
                return
            }

            let tempURL = self.makeTempURL()
            movieOut.startRecording(to: tempURL, recordingDelegate: self)
        }
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self, let movieOut = self.movieOutput, movieOut.isRecording else { return }
            movieOut.stopRecording()
        }
    }

    // MARK: - Zoom

    func setZoom(_ factor: CGFloat, animated: Bool = true) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice else { return }
            let clamped = min(max(factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            do {
                try device.lockForConfiguration()
                if animated {
                    device.ramp(toVideoZoomFactor: clamped, withRate: 8.0)
                } else {
                    device.videoZoomFactor = clamped
                }
                device.unlockForConfiguration()
                Task { @MainActor in
                    self.currentZoomFactor = clamped
                }
            } catch {
                self.logger.error("Zoom failed: \(error)")
            }
        }
    }

    func handlePinchZoom(scale: CGFloat, initialZoom: CGFloat) {
        setZoom(initialZoom * scale, animated: false)
    }

    // MARK: - Flash

    func toggleFlash() {
        isFlashEnabled.toggle()
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = self.isFlashEnabled ? .on : .off
                device.unlockForConfiguration()
            } catch {
                self.logger.error("Flash toggle failed: \(error)")
            }
        }
    }

    // MARK: - Focus

    func focus(at point: CGPoint, in viewSize: CGSize) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice else { return }
            let devicePoint = CGPoint(
                x: point.y / viewSize.height,
                y: 1.0 - (point.x / viewSize.width)
            )
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
                Task { @MainActor in
                    self.focusPoint = point
                    try? await Task.sleep(for: .seconds(1.5))
                    self.focusPoint = nil
                }
            } catch {
                self.logger.error("Focus failed: \(error)")
            }
        }
    }

    // MARK: - Teardown

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

    // MARK: - Helpers

    private func makeTempURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let tempDir = appSupport.appendingPathComponent("PrivateBox/temp", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension VideoRecordingVM: AVCaptureFileOutputRecordingDelegate {

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        Task { @MainActor in
            self.logger.info("Recording started: \(fileURL.lastPathComponent)")
            self.isRecording = true
            self.recordingDuration = 0
            self.recordingTimer?.invalidate()
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
                let nsError = recordingError as NSError
                if nsError.domain == AVFoundationErrorDomain && nsError.code == -11806 {
                    self.logger.info("Recording stopped by user, saving...")
                } else {
                    self.logger.error("Recording failed: \(recordingError.localizedDescription)")
                    try? FileManager.default.removeItem(at: url)
                    return
                }
            }

            // Save video to PrivateBox
            let saved = SecureStorage.shared.saveVideoFile(from: url)
            if let fileId = saved {
                self.logger.info("Video saved: \(fileId)")
                // Signal to navigate to BOX
                self.didFinishSaving = true
            } else {
                self.logger.error("Failed to save video")
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
