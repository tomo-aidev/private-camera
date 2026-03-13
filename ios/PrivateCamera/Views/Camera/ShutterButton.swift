import SwiftUI

/// Shutter button with photo/video modes:
/// - Photo mode: tap to capture, white circle
/// - Video mode: tap to start/stop recording, red ring animation during recording
///
/// Uses only tap gesture (no long-press) to avoid gesture conflicts that break video recording.
struct ShutterButton: View {
    let mode: CameraMode
    let isRecording: Bool
    let onTap: () -> Void

    @State private var isPressed = false
    @State private var recordingProgress: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(outerRingColor.opacity(0.3), lineWidth: 3)
                .frame(width: 88, height: 88)
                .scaleEffect(isPressed ? 1.1 : 1.0)
                .animation(.easeOut(duration: 0.3), value: isPressed)

            // Recording progress ring (video mode)
            if mode == .video && isRecording {
                Circle()
                    .trim(from: 0, to: recordingProgress)
                    .stroke(.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 88, height: 88)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1.0), value: recordingProgress)
            }

            // Main circle
            Circle()
                .fill(mainFill)
                .frame(width: 76, height: 76)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                .scaleEffect(isRecording ? pulseScale : 1.0)

            // Inner ring / stop square
            if mode == .video && isRecording {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.red)
                    .frame(width: 32, height: 32)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Circle()
                    .stroke(Color.black.opacity(0.05), lineWidth: 2)
                    .frame(width: 64, height: 64)
            }
        }
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .animation(.easeInOut(duration: 0.075), value: isPressed)
        .contentShape(Circle())
        .onTapGesture {
            AppTheme.heavyImpact()
            withAnimation {
                isPressed = true
            }
            onTap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation {
                    isPressed = false
                }
            }
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                startPulseAnimation()
            } else {
                pulseScale = 1.0
                recordingProgress = 0
            }
        }
    }

    private var mainFill: Color {
        if mode == .video {
            return isRecording ? .white.opacity(0.9) : .red.opacity(0.85)
        }
        return .white
    }

    private var outerRingColor: Color {
        if mode == .video {
            return .red
        }
        return AppTheme.accentGreen
    }

    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulseScale = 1.05
        }
        // Animate progress ring
        withAnimation(.linear(duration: 60)) {
            recordingProgress = 1.0
        }
    }
}
