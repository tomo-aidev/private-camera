import SwiftUI

/// Settings screen with privacy controls, camera settings, and app info.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var privacySettings = PrivacySettingsManager.shared
    @ObservedObject private var locationManager = LocationManager.shared
    @State private var showAutoRecordAlert = false
    @State private var showLocationDeniedAlert = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Privacy Section
                Section {
                    // Location toggle with permission handling
                    privacyToggle(
                        icon: "location.slash",
                        iconColor: .blue,
                        title: "位置情報を含めない",
                        subtitle: locationSubtitle,
                        isOn: Binding(
                            get: { privacySettings.removeLocation },
                            set: { newValue in
                                if !newValue {
                                    // User wants to INCLUDE location → request permission
                                    handleLocationToggleOn()
                                } else {
                                    // User wants to EXCLUDE location → no permission needed
                                    privacySettings.removeLocation = true
                                    LocationManager.shared.stopUpdating()
                                }
                            }
                        )
                    )

                    privacyToggle(
                        icon: "calendar.badge.minus",
                        iconColor: .orange,
                        title: "日付を含めない",
                        subtitle: "撮影日時の情報を除外します",
                        isOn: $privacySettings.removeDateTime
                    )

                    privacyToggle(
                        icon: "iphone.slash",
                        iconColor: .purple,
                        title: "端末情報を含めない",
                        subtitle: "機種名・ソフトウェア情報を除外します",
                        isOn: $privacySettings.removeDeviceInfo
                    )
                } header: {
                    Label("プライバシー", systemImage: "shield.checkered")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.accentGreen)
                } footer: {
                    Text("有効にすると、保存時に該当するEXIFメタデータが自動的に削除されます。無効にすると該当情報が写真に含まれます。")
                        .font(.system(size: 12))
                }

                // MARK: - Launch Section
                Section {
                    privacyToggle(
                        icon: "video.fill",
                        iconColor: .red,
                        title: "起動時に自動録画",
                        subtitle: "アプリ起動・復帰時に自動でビデオ録画を開始します",
                        isOn: Binding(
                            get: { privacySettings.autoRecordOnLaunch },
                            set: { newValue in
                                privacySettings.autoRecordOnLaunch = newValue
                                if newValue {
                                    showAutoRecordAlert = true
                                }
                            }
                        )
                    )
                } header: {
                    Label("起動設定", systemImage: "power")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.red)
                }

                // MARK: - Photo Settings Section
                Section {
                    settingsPicker(
                        icon: "camera",
                        iconColor: .blue,
                        title: "解像度",
                        selection: Binding(
                            get: { privacySettings.photoResolution },
                            set: { privacySettings.photoResolution = $0 }
                        ),
                        options: PhotoResolution.allCases,
                        labelForOption: { $0.rawValue }
                    )
                } header: {
                    Label("写真", systemImage: "photo")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.blue)
                }

                // MARK: - Video Settings Section
                Section {
                    settingsPicker(
                        icon: "video",
                        iconColor: .red,
                        title: "解像度",
                        selection: Binding(
                            get: { privacySettings.videoResolution },
                            set: { privacySettings.videoResolution = $0 }
                        ),
                        options: VideoResolution.allCases,
                        labelForOption: { $0.rawValue }
                    )

                    settingsPicker(
                        icon: "speedometer",
                        iconColor: .orange,
                        title: "フレームレート",
                        selection: Binding(
                            get: { privacySettings.videoFrameRate },
                            set: { privacySettings.videoFrameRate = $0 }
                        ),
                        options: VideoFrameRate.allCases,
                        labelForOption: { $0.label }
                    )
                } header: {
                    Label("ビデオ", systemImage: "video")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.red)
                }

                // MARK: - Legal Section
                Section {
                    NavigationLink {
                        TermsOfServiceView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 18))
                                .foregroundColor(.gray)
                                .frame(width: 28)
                            Text("利用規約")
                                .font(.system(size: 16, weight: .medium))
                        }
                    }

                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "hand.raised")
                                .font(.system(size: 18))
                                .foregroundColor(.gray)
                                .frame(width: 28)
                            Text("プライバシーポリシー")
                                .font(.system(size: 16, weight: .medium))
                        }
                    }
                } header: {
                    Label("法的情報", systemImage: "building.columns")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.gray)
                }

                // MARK: - App Info Section
                Section {
                    HStack {
                        Text("バージョン")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("ビルド")
                        Spacer()
                        Text(buildNumber)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("アプリ情報", systemImage: "info.circle")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.primary)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                    }
                }
            }
            .alert("自動録画が有効になりました", isPresented: $showAutoRecordAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("次回のアプリ起動時、またはバックグラウンドからの復帰時に自動でビデオ録画が開始されます。")
            }
            .alert("位置情報の許可が必要です", isPresented: $showLocationDeniedAlert) {
                Button("設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("キャンセル", role: .cancel) {
                    // Revert: keep location excluded
                    privacySettings.removeLocation = true
                }
            } message: {
                Text("写真に位置情報を含めるには、「設定」アプリでKesu Cameraの位置情報アクセスを許可してください。")
            }
        }
    }

    // MARK: - Location Permission

    private var locationSubtitle: String {
        if !privacySettings.removeLocation && !locationManager.isAuthorized {
            return "GPS座標をEXIFから除外します（位置情報の許可が必要）"
        }
        return "GPS座標をEXIFから除外します"
    }

    private func handleLocationToggleOn() {
        // User turned OFF "remove location" → wants to INCLUDE location
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            // First time — request permission, then set toggle based on result
            privacySettings.removeLocation = false
            LocationManager.shared.requestPermission()
        case .authorizedWhenInUse, .authorizedAlways:
            // Already authorized
            privacySettings.removeLocation = false
            LocationManager.shared.startUpdating()
        case .denied, .restricted:
            // Permission denied — show alert to go to Settings
            showLocationDeniedAlert = true
        @unknown default:
            privacySettings.removeLocation = false
        }
    }

    // MARK: - Privacy Toggle Row

    private func privacyToggle(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .tint(AppTheme.accentGreen)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Settings Picker Row

    private func settingsPicker<T: Hashable>(
        icon: String,
        iconColor: Color,
        title: String,
        selection: Binding<T>,
        options: [T],
        labelForOption: @escaping (T) -> String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 28)

            Text(title)
                .font(.system(size: 16, weight: .medium))

            Spacer()

            Picker("", selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(labelForOption(option)).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(AppTheme.primary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - App Info

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
