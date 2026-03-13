import SwiftUI

/// Mode switcher (写真 / ビデオ) for camera capture modes.
struct ModeSwitcherView: View {
    @Binding var currentMode: CameraMode
    let onModeChange: (CameraMode) -> Void

    var body: some View {
        HStack(spacing: 32) {
            ForEach(CameraMode.allCases, id: \.self) { mode in
                Button {
                    AppTheme.selectionFeedback()
                    currentMode = mode
                    onModeChange(mode)
                } label: {
                    VStack(spacing: 8) {
                        Text(mode.rawValue)
                            .font(.system(size: 12, weight: .bold))
                            .tracking(2)
                            .foregroundColor(mode == currentMode ? .white : .white.opacity(0.4))

                        // Active indicator dot
                        Circle()
                            .fill(mode == currentMode ? AppTheme.accentGreen : .clear)
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
    }
}
