import SwiftUI
import Photos

/// Main camera capture screen with timer, video recording, and post-capture animation.
struct CameraView: View {
    @StateObject private var engine = CameraEngine()
    @State private var initialPinchZoom: CGFloat = 1.0
    @State private var showSettings = false
    @State private var navigateToBox = false
    @State private var showTimerPicker = false
    @State private var showVideoRecording = false
    @State private var autoStartRecording = false
    @State private var hasCheckedAutoRecord = false
    @Environment(\.scenePhase) private var scenePhase

    // Post-capture animation
    @State private var capturedThumbnail: UIImage?
    @State private var showCaptureAnimation = false
    @State private var captureAnimationOffset: CGSize = .zero
    @State private var captureAnimationScale: CGFloat = 1.0
    @State private var captureAnimationOpacity: CGFloat = 1.0
    @Namespace private var captureNamespace

    var body: some View {
        ZStack {
            // MARK: - Viewfinder
            CameraPreviewView(session: engine.session)
                .ignoresSafeArea()
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            AppTheme.lightImpact()
                            engine.focus(at: value.location, in: UIScreen.main.bounds.size)
                        }
                )
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            engine.handlePinchZoom(scale: value.magnification, initialZoom: initialPinchZoom)
                        }
                        .onEnded { _ in
                            initialPinchZoom = engine.currentZoomFactor
                        }
                )

            // Grid overlay
            if engine.isGridVisible {
                GridOverlayView()
                    .ignoresSafeArea()
            }

            // Focus ring
            if let focusPoint = engine.focusPoint {
                FocusRingView(position: focusPoint)
            }

            // MARK: - UI Layers
            VStack {
                header
                Spacer()
                footer
            }

            // Timer picker overlay
            if showTimerPicker {
                VStack {
                    TimerControlView(
                        timerDuration: $engine.timerDuration,
                        isShowing: $showTimerPicker
                    )
                    .padding(.top, 60)
                    Spacer()
                }
                .transition(.opacity)
            }

            // Timer countdown overlay
            if engine.isTimerRunning && engine.timerCountdown > 0 {
                TimerCountdownOverlay(countdown: engine.timerCountdown)
            }

            // Post-capture animation
            if showCaptureAnimation, let thumb = capturedThumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(3.0/4.0, contentMode: .fit)
                    .frame(width: UIScreen.main.bounds.width)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .scaleEffect(captureAnimationScale)
                    .offset(captureAnimationOffset)
                    .opacity(captureAnimationOpacity)
                    .allowsHitTesting(false)
            }

        }
        .background(AppTheme.backgroundDark)
        .statusBarHidden()
        .task {
            await engine.setup()
            engine.start()

            // Auto-record on launch check
            if !hasCheckedAutoRecord {
                hasCheckedAutoRecord = true
                if PrivacySettingsManager.shared.autoRecordOnLaunch {
                    engine.stop() // Stop photo session to avoid conflict with video session
                    autoStartRecording = true
                    showVideoRecording = true
                }
            }
        }
        .onDisappear {
            engine.stop()
        }
        .fullScreenCover(isPresented: $navigateToBox) {
            PasscodeView()
        }
        .fullScreenCover(isPresented: $showVideoRecording) {
            if autoStartRecording {
                AutoRecordView()
                    .onDisappear {
                        autoStartRecording = false
                    }
            } else {
                VideoRecordingView(autoStart: false)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active &&
               PrivacySettingsManager.shared.autoRecordOnLaunch &&
               !showVideoRecording && !navigateToBox {
                autoStartRecording = true
                showVideoRecording = true
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
                engine.toggleFlash()
            } label: {
                Image(systemName: engine.isFlashEnabled ? "bolt.fill" : "bolt.slash")
                    .font(.system(size: 18))
                    .foregroundColor(engine.isFlashEnabled ? AppTheme.primary : .white.opacity(0.8))
                    .frame(width: 44, height: 44)
            }
            Spacer()

            HStack(spacing: 20) {
                // Timer button
                Button {
                    AppTheme.lightImpact()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showTimerPicker.toggle()
                    }
                } label: {
                    ZStack {
                        Image(systemName: "timer")
                            .font(.system(size: 18))
                            .foregroundColor(engine.timerDuration > 0 ? AppTheme.accentGreen : .white.opacity(0.8))
                            .frame(width: 44, height: 44)

                        if engine.timerDuration > 0 {
                            Text("\(engine.timerDuration)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(AppTheme.accentGreen)
                                .offset(x: 10, y: -8)
                        }
                    }
                }

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
            ZoomArcView(
                thresholds: engine.zoomThresholds,
                currentZoom: $engine.currentZoomFactor,
                displayDivisor: engine.zoomDisplayDivisor,
                onZoomSelected: { factor in
                    engine.setZoom(factor)
                }
            )
            .padding(.bottom, 16)

            // Mode switcher
            ModeSwitcherView(
                currentMode: $engine.currentMode,
                onModeChange: { mode in
                    if mode == .video {
                        // Reset to photo mode immediately and open video screen
                        engine.currentMode = .photo
                        showVideoRecording = true
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
                    mode: engine.currentMode,
                    isRecording: false,
                    onTap: {
                        handleShutterTap()
                    }
                )

                Spacer()

                // Camera flip button
                Button {
                    AppTheme.mediumImpact()
                    engine.switchCamera()
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

    // MARK: - Actions

    private func handleShutterTap() {
        // Photo capture with optional timer
        Task {
            let image = await engine.captureWithTimer()
            if let image {
                AppTheme.successNotification()
                playCaptureAnimation(image: image)
            }
        }
    }

    private func playCaptureAnimation(image: UIImage) {
        // Resize to target resolution, then save based on save destination
        let settings = PrivacySettingsManager.shared.currentScrubSettings
        let resolution = PrivacySettingsManager.shared.photoResolution
        let destination = PrivacySettingsManager.shared.saveDestination

        // Build capture context for metadata injection
        let captureContext = ExifScrubber.CaptureContext(
            location: settings.keepLocation ? LocationManager.shared.getLatestCoordinates() : nil,
            captureDate: Date(),
            captureDevice: engine.currentDevice
        )

        Task {
            let resized = resolution.resized(image)

            switch destination {
            case .box:
                // Save to Private BOX (encrypted)
                _ = SecureStorage.shared.saveImage(resized, scrubSettings: settings, captureContext: captureContext)

            case .cameraRoll:
                // Save directly to Camera Roll with metadata
                saveToCameraRoll(image: resized, scrubSettings: settings, captureContext: captureContext)
            }
        }

        capturedThumbnail = image
        captureAnimationScale = 1.0
        captureAnimationOffset = .zero
        captureAnimationOpacity = 1.0
        showCaptureAnimation = true

        // Calculate target position (private box button, bottom-left)
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        let targetX: CGFloat = -(screenWidth / 2 - 60) // box button position
        let targetY: CGFloat = screenHeight / 2 - 120

        withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
            captureAnimationScale = 0.05
            captureAnimationOffset = CGSize(width: targetX, height: targetY)
            captureAnimationOpacity = 0.0
        }

        // After animation completes, stay on camera for continuous shooting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            showCaptureAnimation = false
            capturedThumbnail = nil
            // Do NOT navigate to ReviewView — stay on camera
        }
    }

    // MARK: - Camera Roll Save

    /// Save photo directly to Camera Roll with metadata applied.
    private func saveToCameraRoll(image: UIImage, scrubSettings: ExifScrubber.ScrubSettings, captureContext: ExifScrubber.CaptureContext) {
        guard let jpegData = image.jpegData(compressionQuality: 0.95) else { return }

        // Step 1: Scrub all metadata first
        guard var processedData = ExifScrubber.scrub(jpegData: jpegData, settings: .removeAll) else { return }

        // Step 2: Inject only the metadata user wants to keep
        let needsInjection = scrubSettings.keepLocation || scrubSettings.keepDateTime || scrubSettings.keepDeviceInfo
        if needsInjection {
            if let injected = ExifScrubber.injectMetadata(into: processedData, settings: scrubSettings, context: captureContext) {
                processedData = injected
            }
        }

        // Step 3: Save to Camera Roll
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }

            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: processedData, options: nil)
                request.creationDate = captureContext.captureDate
                if let location = captureContext.location {
                    request.location = location
                }
            } completionHandler: { success, error in
                if !success {
                    print("Failed to save to Camera Roll: \(error?.localizedDescription ?? "unknown")")
                }
            }
        }
    }

}
