import SwiftUI

@main
struct PrivateCameraApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        // Verify data persistence on every launch.
        // This ensures photo data survives app updates during development.
        DataPersistenceGuard.shared.verifyOnLaunch()
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                CameraView()
                    .preferredColorScheme(.dark)
            } else {
                OnboardingView()
                    .preferredColorScheme(.dark)
            }
        }
    }
}
