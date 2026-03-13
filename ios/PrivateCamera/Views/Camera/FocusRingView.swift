import SwiftUI

/// Animated focus ring overlay matching the HTML design:
/// Green-bordered square with corner accents.
struct FocusRingView: View {
    let position: CGPoint
    @State private var scale: CGFloat = 1.5
    @State private var opacity: Double = 1.0

    var body: some View {
        ZStack {
            // Main border
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.accentGreen.opacity(0.6), lineWidth: 1)
                .frame(width: 80, height: 80)

            // Corner accents
            ForEach(Corner.allCases, id: \.self) { corner in
                CornerAccent(corner: corner)
            }
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .position(position)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                scale = 1.0
            }
            // Fade out after delay
            withAnimation(.easeOut(duration: 0.3).delay(1.2)) {
                opacity = 0
            }
        }
    }

    enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    struct CornerAccent: View {
        let corner: Corner
        private let size: CGFloat = 12
        private let lineWidth: CGFloat = 2

        var body: some View {
            Path { path in
                switch corner {
                case .topLeft:
                    path.move(to: CGPoint(x: 0, y: size))
                    path.addLine(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: size, y: 0))
                case .topRight:
                    path.move(to: CGPoint(x: -size, y: 0))
                    path.addLine(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: 0, y: size))
                case .bottomLeft:
                    path.move(to: CGPoint(x: 0, y: -size))
                    path.addLine(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: size, y: 0))
                case .bottomRight:
                    path.move(to: CGPoint(x: -size, y: 0))
                    path.addLine(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: 0, y: -size))
                }
            }
            .stroke(AppTheme.accentGreen, lineWidth: lineWidth)
            .frame(width: size, height: size)
            .offset(cornerOffset)
        }

        private var cornerOffset: CGSize {
            let half: CGFloat = 40 + 4 // half of 80px ring + spacing
            switch corner {
            case .topLeft: return CGSize(width: -half, height: -half)
            case .topRight: return CGSize(width: half, height: -half)
            case .bottomLeft: return CGSize(width: -half, height: half)
            case .bottomRight: return CGSize(width: half, height: half)
            }
        }
    }
}
