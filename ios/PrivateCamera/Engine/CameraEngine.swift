import AVFoundation
import Combine
import SwiftUI
import os.log

// MARK: - Camera Mode

enum CameraMode: String, CaseIterable {
    case photo = "写真"
    case video = "ビデオ"
}

enum CameraPosition {
    case back, front
}

// MARK: - CameraEngine

@MainActor
final class CameraEngine: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isSessionRunning = false
    @Published var currentMode: CameraMode = .photo
    @Published var currentPosition: CameraPosition = .back
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var zoomThresholds: [(label: String, factor: CGFloat)] = []
    @Published var zoomDisplayDivisor: CGFloat = 1.0
    @Published var capturedImage: UIImage?
    @Published var focusPoint: CGPoint? = nil
    @Published var exposureValue: Float = 0
    @Published var isFlashEnabled = false
    @Published var isHDRActive = false
    @Published var isGridVisible = true
    @Published var error: CameraError?
    @Published var timerDuration: Int = 0 // 0 = off, 3 = 3s, 10 = 10s
    @Published var timerCountdown: Int = 0
    @Published var isTimerRunning = false

    enum CameraError: LocalizedError {
        case noCameraAvailable
        case configurationFailed(String)
        case captureFailed(String)
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .noCameraAvailable: return "カメラが利用できません"
            case .configurationFailed(let msg): return "設定エラー: \(msg)"
            case .captureFailed(let msg): return "撮影エラー: \(msg)"
            case .permissionDenied: return "カメラへのアクセスが拒否されました"
            }
        }
    }

    // MARK: - Internal Properties

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.privatecamera.session", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.privatecamera", category: "CameraEngine")
    private let optimizer = CameraHardwareOptimizer.shared

    /// The currently active AVCaptureDevice (exposed for metadata injection).
    private(set) var currentDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private var photoOutput: AVCapturePhotoOutput?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    // Silent capture delegate
    private(set) var silentCapture: SilentCaptureEngine?

    private var keyValueObservations = [NSKeyValueObservation]()

    // MARK: - Lifecycle

    override init() {
        super.init()
    }

    func setup() async {
        // Check permission
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                self.error = .permissionDenied
                return
            }
        default:
            self.error = .permissionDenied
            return
        }

        // Discover hardware
        let spec = optimizer.discover()

        // Configure session on background queue
        sessionQueue.async { [weak self] in
            self?.configureSession(spec: spec)
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            Task { @MainActor in
                self.isSessionRunning = self.session.isRunning
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            Task { @MainActor in
                self.isSessionRunning = false
            }
        }
    }

    // MARK: - Session Configuration

    private func configureSession(spec: DeviceCameraSpec) {
        // Use the logical multi-camera for seamless zoom, fallback to best single
        guard let camera = spec.logicalMultiCamera ?? spec.bestBackCamera else {
            logger.error("No back camera found")
            Task { @MainActor in
                self.error = .noCameraAvailable
            }
            return
        }

        // Find the best format BEFORE session configuration.
        // This probes formats by temporarily setting them on the device.
        let bestFormat = optimizer.findBestFormatWithFullZoomRange(device: camera)

        session.beginConfiguration()

        // CRITICAL: Use .inputPriority instead of .photo
        // .photo preset auto-selects a format that may exclude ultra-wide zoom range
        // .inputPriority lets us manually select a format with full zoom support
        // .inputPriority also supports all output types (photo + movie) without conflicts
        session.sessionPreset = .inputPriority

        do {
            // Video input
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
                self.videoInput = input
                self.currentDevice = camera
            }

            // Photo output (used as fallback; primary capture is buffer-based)
            let photoOut = AVCapturePhotoOutput()
            photoOut.isHighResolutionCaptureEnabled = true
            photoOut.maxPhotoQualityPrioritization = .quality
            if session.canAddOutput(photoOut) {
                session.addOutput(photoOut)
                self.photoOutput = photoOut
            }

            // Video data output for silent capture
            let videoDataOut = AVCaptureVideoDataOutput()
            videoDataOut.alwaysDiscardsLateVideoFrames = false
            videoDataOut.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            if session.canAddOutput(videoDataOut) {
                session.addOutput(videoDataOut)
                self.videoDataOutput = videoDataOut

                // Configure connection for max resolution
                if let connection = videoDataOut.connection(with: .video) {
                    connection.videoRotationAngle = 90
                }
            }

            // Apply the selected format AFTER adding outputs
            // (adding outputs can affect format compatibility)
            if let format = bestFormat {
                try camera.lockForConfiguration()
                camera.activeFormat = format
                // Must manually set frame rate with .inputPriority
                camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                if format.isVideoHDRSupported {
                    camera.automaticallyAdjustsVideoHDREnabled = false
                    camera.isVideoHDREnabled = true
                }
                camera.unlockForConfiguration()

                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                logger.info("Applied format: \(dims.width)x\(dims.height), zoom: \(camera.minAvailableVideoZoomFactor)-\(camera.maxAvailableVideoZoomFactor)")
            }

            // Setup silent capture engine
            let silent = SilentCaptureEngine(videoDataOutput: videoDataOut)
            self.silentCapture = silent

        } catch {
            logger.error("Session configuration failed: \(error.localizedDescription)")
            Task { @MainActor in
                self.error = .configurationFailed(error.localizedDescription)
            }
        }

        session.commitConfiguration()

        // Configure zoom thresholds AFTER commitConfiguration
        let thresholds = optimizer.zoomThresholds()
        let divisor = optimizer.zoomDisplayDivisor

        // Set initial zoom to "1x" (wide lens) instead of ultra-wide
        // On triple camera, "1x" = first switchover factor (typically raw 2.0)
        let initialZoom: CGFloat
        if let firstSwitch = camera.virtualDeviceSwitchOverVideoZoomFactors.first {
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
    }

    // MARK: - Camera Switching

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let spec = self.optimizer.deviceSpec
            let newPosition: CameraPosition = self.currentPosition == .back ? .front : .back

            let newDevice: AVCaptureDevice?
            if newPosition == .back {
                newDevice = spec?.logicalMultiCamera ?? spec?.bestBackCamera
            } else {
                newDevice = spec?.bestFrontCamera
            }

            guard let device = newDevice else { return }

            self.session.beginConfiguration()

            // Remove current input
            if let currentInput = self.videoInput {
                self.session.removeInput(currentInput)
            }

            do {
                let newInput = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.videoInput = newInput
                    self.currentDevice = device

                    // Re-apply optimal format
                    try self.optimizer.applyOptimalPhotoFormat(to: device)

                    // Update video data output connection
                    if let connection = self.videoDataOutput?.connection(with: .video) {
                        connection.videoRotationAngle = 90
                        if device.position == .front {
                            connection.isVideoMirrored = true
                        }
                    }
                }
            } catch {
                self.logger.error("Failed to switch camera: \(error)")
            }

            self.session.commitConfiguration()

            Task { @MainActor in
                self.currentPosition = newPosition
                self.currentZoomFactor = 1.0
            }
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

    /// Handle pinch gesture zoom
    func handlePinchZoom(scale: CGFloat, initialZoom: CGFloat) {
        let newFactor = initialZoom * scale
        setZoom(newFactor, animated: false)
    }

    // MARK: - Focus & Exposure

    func focus(at point: CGPoint, in viewSize: CGSize) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice else { return }

            // Convert point to device coordinates
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
                    // Auto-dismiss focus indicator
                    try? await Task.sleep(for: .seconds(1.5))
                    self.focusPoint = nil
                }
            } catch {
                self.logger.error("Focus failed: \(error)")
            }
        }
    }

    // MARK: - Flash

    func toggleFlash() {
        isFlashEnabled.toggle()
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice else { return }
            if device.hasTorch {
                do {
                    try device.lockForConfiguration()
                    device.torchMode = self.isFlashEnabled ? .on : .off
                    device.unlockForConfiguration()
                } catch {
                    self.logger.error("Flash toggle failed: \(error)")
                }
            }
        }
    }

    // MARK: - Silent Capture

    /// Capture a full-resolution still frame silently from the video buffer.
    func capturePhoto() async -> UIImage? {
        guard let silentCapture else {
            logger.error("Silent capture engine not initialized")
            return nil
        }

        let image = await silentCapture.captureStillImage()

        await MainActor.run {
            self.capturedImage = image
        }

        return image
    }

    // MARK: - Timer Capture

    /// Cycle timer duration: off → 3s → 10s → off
    func cycleTimer() {
        switch timerDuration {
        case 0: timerDuration = 3
        case 3: timerDuration = 10
        default: timerDuration = 0
        }
    }

    /// Capture with optional timer delay
    func captureWithTimer() async -> UIImage? {
        if timerDuration > 0 {
            isTimerRunning = true
            timerCountdown = timerDuration
            for i in stride(from: timerDuration, through: 1, by: -1) {
                timerCountdown = i
                try? await Task.sleep(for: .seconds(1))
                if !isTimerRunning { return nil } // cancelled
            }
            isTimerRunning = false
            timerCountdown = 0
        }
        return await capturePhoto()
    }

    func cancelTimer() {
        isTimerRunning = false
        timerCountdown = 0
    }

    // MARK: - Preview Layer

    nonisolated func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }
}

