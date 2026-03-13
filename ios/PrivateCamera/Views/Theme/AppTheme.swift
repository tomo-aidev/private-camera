import SwiftUI

enum AppTheme {
    // MARK: - Colors (from Tailwind config)

    /// Primary orange accent (#ec5b13)
    static let primary = Color(red: 0.925, green: 0.357, blue: 0.075)

    /// Green accent for focus/active states (#44e47e)
    static let accentGreen = Color(red: 0.267, green: 0.894, blue: 0.494)

    /// Dark background (#221610)
    static let backgroundDark = Color(red: 0.133, green: 0.086, blue: 0.063)

    /// Light background (#f8f6f6)
    static let backgroundLight = Color(red: 0.973, green: 0.965, blue: 0.965)

    /// Review screen dark background (#112117)
    static let reviewBackgroundDark = Color(red: 0.067, green: 0.129, blue: 0.090)

    /// Review screen primary green (#44e47e)
    static let reviewPrimary = Color(red: 0.267, green: 0.894, blue: 0.494)

    // MARK: - Fonts

    static let displayFont = "PublicSans"

    // MARK: - Haptics

    static func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func mediumImpact() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func heavyImpact() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func selectionFeedback() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func successNotification() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
