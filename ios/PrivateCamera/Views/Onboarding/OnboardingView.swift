import SwiftUI
import AVFoundation
import CoreLocation

/// Onboarding flow with 2 screens: permissions and location.
struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            AppTheme.backgroundDark.ignoresSafeArea()

            TabView(selection: $currentPage) {
                // Page 1: Camera & Microphone permissions
                OnboardingPermissionView(onNext: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        currentPage = 1
                    }
                })
                .tag(0)

                // Page 2: Location permission
                OnboardingLocationView(onComplete: {
                    withAnimation(.easeOut(duration: 0.3)) {
                        hasCompletedOnboarding = true
                    }
                })
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentPage)

            // Page indicator
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? AppTheme.accentGreen : Color.white.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .scaleEffect(index == currentPage ? 1.2 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: currentPage)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Permission Screen (Page 1)

struct OnboardingPermissionView: View {
    let onNext: () -> Void
    @State private var cameraGranted = false
    @State private var micGranted = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(AppTheme.primary.opacity(0.15))
                    .frame(width: 120, height: 120)
                Image(systemName: "camera.fill")
                    .font(.system(size: 48))
                    .foregroundColor(AppTheme.primary)
            }
            .padding(.bottom, 32)

            // Title
            Text("はじめに")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 8)

            Text("写真・動画の撮影に必要なため同意が必須です。")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.6))
                .padding(.bottom, 40)

            // Permission status
            VStack(spacing: 16) {
                permissionRow(
                    icon: "camera",
                    title: "カメラ",
                    subtitle: "写真・動画の撮影に必要です",
                    isGranted: cameraGranted
                )
                permissionRow(
                    icon: "mic",
                    title: "マイク",
                    subtitle: "動画撮影時の音声録音に必要です",
                    isGranted: micGranted
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            // Begin button
            Button {
                requestPermissions()
            } label: {
                Text("始める")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppTheme.accentGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 80)
        }
    }

    private func permissionRow(icon: String, title: String, subtitle: String, isGranted: Bool) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(AppTheme.accentGreen)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func requestPermissions() {
        Task {
            // Request camera
            let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            if cameraStatus == .notDetermined {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                await MainActor.run { cameraGranted = granted }
            } else {
                await MainActor.run { cameraGranted = cameraStatus == .authorized }
            }

            // Request microphone
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            if micStatus == .notDetermined {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                await MainActor.run { micGranted = granted }
            } else {
                await MainActor.run { micGranted = micStatus == .authorized }
            }

            // Small delay to show checkmarks, then advance
            try? await Task.sleep(for: .milliseconds(600))
            await MainActor.run { onNext() }
        }
    }
}

// MARK: - Location Screen (Page 2)

struct OnboardingLocationView: View {
    let onComplete: () -> Void
    @State private var locationManager: CLLocationManager?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 120, height: 120)
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
            }
            .padding(.bottom, 32)

            // Title
            Text("位置情報について")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 8)

            Text("撮影した写真のEXIFデータから\n位置情報を自動的に削除できます")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.bottom, 40)

            // Info card
            VStack(alignment: .leading, spacing: 12) {
                infoRow(icon: "shield.checkered", text: "位置情報はデフォルトで削除されます")
                infoRow(icon: "gearshape", text: "設定からいつでも変更できます")
                infoRow(icon: "lock.fill", text: "データは端末内で安全に管理されます")
            }
            .padding(20)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 32)

            Spacer()

            // Buttons — "付与しない" is the primary action (top)
            VStack(spacing: 12) {
                Button {
                    // Don't attach location → go straight to main screen
                    onComplete()
                } label: {
                    Text("位置情報を付与しない")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppTheme.accentGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    // Attach location → request permission, then go to main screen
                    requestLocation()
                } label: {
                    Text("位置情報を付与する")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 80)
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(AppTheme.accentGreen)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))
        }
    }

    private func requestLocation() {
        let manager = CLLocationManager()
        locationManager = manager
        manager.requestWhenInUseAuthorization()

        // Give time for the system dialog, then complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            onComplete()
        }
    }
}
