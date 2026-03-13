import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// Photo editing screen with brightness, contrast, saturation, and rotation.
struct PhotoEditView: View {
    let image: UIImage
    let fileId: String

    @Environment(\.dismiss) private var dismiss
    @State private var brightness: Double = 0
    @State private var contrast: Double = 1.0
    @State private var saturation: Double = 1.0
    @State private var rotation: Double = 0
    @State private var editedImage: UIImage?
    @State private var isSaving = false
    @State private var showSaved = false

    private let context = CIContext()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                    }

                    Spacer()

                    Text("写真を編集")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    Spacer()

                    Button {
                        saveEdited()
                    } label: {
                        Text("保存")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppTheme.accentGreen)
                            .frame(width: 44, height: 44)
                    }
                    .disabled(isSaving)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                // Image preview
                Spacer()

                Image(uiImage: displayImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .rotationEffect(.degrees(rotation))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 16)

                Spacer()

                // Edit controls
                VStack(spacing: 20) {
                    // Rotation button
                    HStack {
                        Spacer()
                        Button {
                            AppTheme.selectionFeedback()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                rotation += 90
                                if rotation >= 360 { rotation = 0 }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "rotate.right")
                                Text("回転")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                        }
                        Spacer()
                    }

                    // Sliders
                    editSlider(
                        icon: "sun.max",
                        label: "明るさ",
                        value: $brightness,
                        range: -0.5...0.5
                    )

                    editSlider(
                        icon: "circle.lefthalf.filled",
                        label: "コントラスト",
                        value: $contrast,
                        range: 0.5...1.5
                    )

                    editSlider(
                        icon: "paintpalette",
                        label: "彩度",
                        value: $saturation,
                        range: 0...2.0
                    )

                    // Reset button
                    Button {
                        AppTheme.lightImpact()
                        withAnimation {
                            brightness = 0
                            contrast = 1.0
                            saturation = 1.0
                            rotation = 0
                        }
                    } label: {
                        Text("リセット")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }

            if showSaved {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(AppTheme.accentGreen)
                    Text("保存しました")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .transition(.opacity)
                .onAppear {
                    AppTheme.successNotification()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var displayImage: UIImage {
        applyFilters(to: image) ?? image
    }

    private func editSlider(icon: String, label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text(String(format: "%.1f", value.wrappedValue))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
            Slider(value: value, in: range)
                .tint(AppTheme.accentGreen)
        }
    }

    private func applyFilters(to inputImage: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: inputImage) else { return nil }

        let filter = CIFilter.colorControls()
        filter.inputImage = ciImage
        filter.brightness = Float(brightness)
        filter.contrast = Float(contrast)
        filter.saturation = Float(saturation)

        guard let outputImage = filter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: inputImage.scale, orientation: inputImage.imageOrientation)
    }

    private func saveEdited() {
        isSaving = true
        Task {
            var finalImage = applyFilters(to: image) ?? image

            // Apply rotation
            if rotation != 0 {
                let rotationSteps = Int(rotation) / 90
                for _ in 0..<(rotationSteps % 4) {
                    finalImage = rotateImage90(finalImage)
                }
            }

            let settings = PrivacySettingsManager.shared.currentScrubSettings
            _ = SecureStorage.shared.saveImage(finalImage, scrubSettings: settings)

            await MainActor.run {
                isSaving = false
                withAnimation {
                    showSaved = true
                }
            }
        }
    }

    private func rotateImage90(_ inputImage: UIImage) -> UIImage {
        let size = CGSize(width: inputImage.size.height, height: inputImage.size.width)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            ctx.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.cgContext.rotate(by: .pi / 2)
            inputImage.draw(in: CGRect(
                x: -inputImage.size.width / 2,
                y: -inputImage.size.height / 2,
                width: inputImage.size.width,
                height: inputImage.size.height
            ))
        }
    }
}
