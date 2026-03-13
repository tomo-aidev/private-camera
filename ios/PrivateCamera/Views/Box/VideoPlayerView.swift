import SwiftUI
import AVKit

/// Full-screen video player for PrivateBox videos.
struct VideoPlayerView: View {
    let fileId: String
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if let errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .font(.headline)
                        .foregroundColor(.white)
                }
            } else {
                ProgressView()
                    .tint(.white)
            }

            // Top bar overlay
            VStack {
                HStack {
                    Button {
                        player?.pause()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.4))
                            .clipShape(Circle())
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 60)

                Spacer()
            }
        }
        .onAppear {
            loadVideo()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private func loadVideo() {
        guard let url = SecureStorage.shared.loadVideoURL(fileId: fileId) else {
            errorMessage = "動画を読み込めません"
            return
        }
        let avPlayer = AVPlayer(url: url)
        self.player = avPlayer
        avPlayer.play()
    }
}
