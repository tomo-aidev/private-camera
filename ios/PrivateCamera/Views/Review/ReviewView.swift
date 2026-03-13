import SwiftUI

/// Confirmation & privacy screen matching _2/code.html design.
/// When opened from album, pass `title: "写真の編集"` and `isAlreadySaved: true`.
struct ReviewView: View {
    let image: UIImage
    var title: String = "確認とプライバシー"
    var isAlreadySaved: Bool = false
    var fileId: String? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var privacySettings = PrivacySettingsManager.shared
    @State private var isSaving = false
    @State private var showSaveSuccess = false

    var body: some View {
        ZStack {
            Color(red: 0.067, green: 0.129, blue: 0.090)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Header
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                    }

                    Spacer()

                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .tracking(-0.3)
                        .foregroundColor(.white)

                    Spacer()

                    // Balance layout
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // MARK: - Content
                ScrollView {
                    VStack(spacing: 0) {
                        // Image preview
                        imagePreview
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)

                        // Privacy settings
                        privacySection
                            .padding(.top, 24)
                    }
                    .padding(.bottom, 120)
                }

                Spacer()
            }

            // MARK: - Bottom Save Button
            VStack {
                Spacer()
                saveButton
            }

            // Save success overlay
            if showSaveSuccess {
                saveSuccessOverlay
            }
        }
    }

    // MARK: - Image Preview

    private var imagePreview: some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(3.0/4.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 20)

            // Mode badge
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.accentGreen)

                Text("プレビューモード")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.4))
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
            .padding(16)
        }
    }

    // MARK: - Privacy Settings

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "shield.checkered")
                    .foregroundColor(AppTheme.accentGreen)
                Text("メタデータ削除")
                    .font(.system(size: 18, weight: .bold))
                    .tracking(-0.3)
            }
            .padding(.horizontal, 16)

            VStack(spacing: 4) {
                PrivacyCheckboxRow(
                    icon: "location.slash",
                    label: "位置情報を削除",
                    isChecked: $privacySettings.removeLocation
                )
                PrivacyCheckboxRow(
                    icon: "calendar.badge.minus",
                    label: "日時情報を削除",
                    isChecked: $privacySettings.removeDateTime
                )
                PrivacyCheckboxRow(
                    icon: "iphone.slash",
                    label: "端末情報を削除",
                    isChecked: $privacySettings.removeDeviceInfo
                )
            }
            .padding(8)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)

            Text("注：チェックした項目のEXIFデータは保存時に完全に削除されます。削除後の復元はできません。")
                .font(.system(size: 12))
                .italic()
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            saveImage()
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .tint(Color(red: 0.067, green: 0.129, blue: 0.090))
                } else {
                    Image(systemName: "checkmark.shield")
                    Text(isAlreadySaved ? "変更を保存" : "メタデータを削除して保存")
                }
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(Color(red: 0.067, green: 0.129, blue: 0.090))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppTheme.accentGreen)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: AppTheme.accentGreen.opacity(0.2), radius: 16, y: 4)
        }
        .disabled(isSaving)
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
        .background(
            LinearGradient(
                colors: [Color(red: 0.067, green: 0.129, blue: 0.090).opacity(0), Color(red: 0.067, green: 0.129, blue: 0.090)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .ignoresSafeArea()
        )
    }

    // MARK: - Save Success Overlay

    private var saveSuccessOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(AppTheme.accentGreen)

            Text("保存完了")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .ignoresSafeArea()
        .transition(.opacity)
        .onAppear {
            AppTheme.successNotification()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        }
    }

    // MARK: - Actions

    private func saveImage() {
        isSaving = true

        let settings = privacySettings.currentScrubSettings

        Task {
            // If editing an already-saved file, delete the old one first
            if isAlreadySaved, let existingId = fileId {
                SecureStorage.shared.deleteImage(fileId: existingId)
            }

            let newFileId = SecureStorage.shared.saveImage(image, scrubSettings: settings)
            await MainActor.run {
                isSaving = false
                if newFileId != nil {
                    withAnimation {
                        showSaveSuccess = true
                    }
                }
            }
        }
    }
}

// MARK: - Subviews

struct PrivacyCheckboxRow: View {
    let icon: String
    let label: String
    @Binding var isChecked: Bool

    var body: some View {
        Button {
            isChecked.toggle()
        } label: {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 24)

                Text(label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundColor(isChecked ? AppTheme.accentGreen : .white.opacity(0.3))
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
