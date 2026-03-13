import SwiftUI

/// Timer selection popup: off / 3s / 10s
struct TimerControlView: View {
    @Binding var timerDuration: Int
    @Binding var isShowing: Bool

    var body: some View {
        HStack(spacing: 16) {
            timerOption(label: "オフ", value: 0)
            timerOption(label: "3秒", value: 3)
            timerOption(label: "10秒", value: 10)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func timerOption(label: String, value: Int) -> some View {
        Button {
            AppTheme.selectionFeedback()
            timerDuration = value
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isShowing = false
            }
        } label: {
            Text(label)
                .font(.system(size: 14, weight: value == timerDuration ? .bold : .medium))
                .foregroundColor(value == timerDuration ? AppTheme.accentGreen : .white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    value == timerDuration
                        ? AppTheme.accentGreen.opacity(0.15)
                        : Color.clear
                )
                .clipShape(Capsule())
        }
    }
}

/// Full-screen countdown overlay with bouncy number animation
struct TimerCountdownOverlay: View {
    let countdown: Int

    @State private var scale: CGFloat = 2.0
    @State private var opacity: CGFloat = 0.0

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            Text("\(countdown)")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 20)
                .scaleEffect(scale)
                .opacity(opacity)
        }
        .onAppear {
            // Bouncy entrance
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                scale = 1.0
                opacity = 1.0
            }
            // Fade out
            withAnimation(.easeOut(duration: 0.3).delay(0.5)) {
                opacity = 0.6
            }
        }
        .onChange(of: countdown) { _, _ in
            scale = 2.0
            opacity = 0.0
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                scale = 1.0
                opacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.5)) {
                opacity = 0.6
            }
        }
    }
}
