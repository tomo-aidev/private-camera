import SwiftUI
import Photos

/// Private photo gallery matching box_2/code.html design.
struct PrivateBoxView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    var onDismissToCamera: (() -> Void)?
    @State private var files: [SecureStorage.StoredFile] = []
    @State private var showAutoRecord = false
    @State private var suppressAutoRecord = true
    @State private var selectedTab: BoxTab = .all
    @State private var isEditing = false
    @State private var selectedFiles: Set<String> = Set()
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var selectedFileForEdit: SecureStorage.StoredFile?
    @State private var selectedVideoFile: SecureStorage.StoredFile?
    @State private var showSaveSuccess = false
    @State private var showSaveError = false
    @State private var showStorageWarning = false
    @State private var storageWarningMessage = ""
    @State private var showSaveDestination = false
    @State private var showPhotoPermissionDenied = false
    // Drag selection
    @State private var cellFrames: [String: CGRect] = [:]
    @State private var isDragSelecting = false
    @State private var dragAddMode = true
    @State private var lastDragHitId: String? = nil

    enum BoxTab: String, CaseIterable {
        case all = "すべて"
        case video = "ビデオ"
    }

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // MARK: - Compact Header (title + tabs + select in one row)
                HStack(spacing: 0) {
                    // Tab buttons (left-aligned)
                    HStack(spacing: 16) {
                        ForEach(BoxTab.allCases, id: \.self) { tab in
                            Button {
                                selectedTab = tab
                            } label: {
                                Text(tab.rawValue)
                                    .font(.system(size: 14, weight: tab == selectedTab ? .bold : .medium))
                                    .foregroundColor(tab == selectedTab ? AppTheme.primary : .secondary)
                                    .padding(.vertical, 6)
                            }
                            .overlay(alignment: .bottom) {
                                if tab == selectedTab {
                                    Rectangle()
                                        .fill(AppTheme.primary)
                                        .frame(height: 2)
                                }
                            }
                        }
                    }

                    Spacer()

                    // Select / Done button
                    Button {
                        isEditing.toggle()
                        if !isEditing { selectedFiles.removeAll() }
                    } label: {
                        Text(isEditing ? "完了" : "選択")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.primary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()

                // MARK: - Grid
                ScrollView {
                    if files.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(filteredFiles) { file in
                                PhotoGridCell(
                                    file: file,
                                    thumbnail: thumbnails[file.id],
                                    isEditing: isEditing,
                                    isSelected: selectedFiles.contains(file.id),
                                    onTap: {
                                        if isEditing {
                                            toggleSelection(file.id)
                                        } else {
                                            openFile(file)
                                        }
                                    }
                                )
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: CellFramePreferenceKey.self,
                                            value: [file.id: geo.frame(in: .named("gridScroll"))]
                                        )
                                    }
                                )
                            }
                        }
                        .padding(4)
                    }
                }
                .coordinateSpace(name: "gridScroll")
                .onPreferenceChange(CellFramePreferenceKey.self) { frames in
                    cellFrames = frames
                }
                .simultaneousGesture(
                    isEditing ? DragGesture(minimumDistance: 15, coordinateSpace: .named("gridScroll"))
                        .onChanged { value in
                            handleDragChanged(at: value.location, startLocation: value.startLocation)
                        }
                        .onEnded { _ in
                            isDragSelecting = false
                            lastDragHitId = nil
                        }
                    : nil
                )

                // MARK: - Bottom Bar
                if isEditing && !selectedFiles.isEmpty {
                    editingBottomBar
                } else {
                    standardBottomBar
                }
            }
            .background(Color(.systemBackground))

            // Save success toast
            if showSaveSuccess {
                saveToast(message: "カメラロールに保存しました", icon: "checkmark.circle.fill", color: AppTheme.accentGreen)
            }

            // Save error toast
            if showSaveError {
                saveToast(message: "保存に失敗しました。設定で写真へのアクセスを許可してください。", icon: "exclamationmark.triangle.fill", color: .orange)
            }
        }
        .onAppear {
            loadFiles()
            checkStorageWarning()
            // Suppress auto-record for 3 seconds to avoid false triggers during view transitions
            suppressAutoRecord = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                suppressAutoRecord = false
            }
        }
        .fullScreenCover(item: $selectedFileForEdit) { file in
            if let image = SecureStorage.shared.loadImage(fileId: file.id) {
                ReviewView(
                    image: image,
                    title: "写真の編集",
                    isAlreadySaved: true,
                    fileId: file.id
                )
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text("画像を読み込めません")
                        .font(.headline)
                    Button("閉じる") {
                        selectedFileForEdit = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .fullScreenCover(item: $selectedVideoFile) { file in
            VideoPlayerView(fileId: file.id, title: "動画再生")
        }
        .fullScreenCover(isPresented: $showAutoRecord) {
            AutoRecordView(navigateToBoxAfterSave: false)
                .onDisappear {
                    // Reload files to show newly recorded video
                    loadFiles()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active &&
               !suppressAutoRecord &&
               PrivacySettingsManager.shared.autoRecordOnLaunch &&
               !showAutoRecord {
                showAutoRecord = true
            }
        }
        .alert("BOXの整理をお願いします", isPresented: $showStorageWarning) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(storageWarningMessage)
        }
        .confirmationDialog("保存方法", isPresented: $showSaveDestination, titleVisibility: .visible) {
            Button {
                PrivacySettingsManager.shared.saveDestination = .box
            } label: {
                Label("BOXに入れる", systemImage: "lock.shield")
            }
            Button {
                requestCameraRollPermissionAndSet()
            } label: {
                Label("カメラロールに直接保存する", systemImage: "photo.on.rectangle")
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            let current = PrivacySettingsManager.shared.saveDestination
            Text("現在: \(current.label)\n撮影した写真・ビデオの保存先を選択してください。")
        }
        .alert("写真アクセスの許可が必要です", isPresented: $showPhotoPermissionDenied) {
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("カメラロールに保存するには、「設定」アプリで写真へのアクセスを許可してください。")
        }
    }

    // MARK: - Save Toast

    private func saveToast(message: String, icon: String, color: Color) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(message)
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(radius: 8)
            .padding(.bottom, 100)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Filtered Files

    private var filteredFiles: [SecureStorage.StoredFile] {
        switch selectedTab {
        case .all: return files
        case .video: return files.filter { $0.mediaType == .video }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text("プライベートBOXは空です")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)

            Text("撮影した写真はここに安全に保存されます")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    // MARK: - Editing Bottom Bar

    private var editingBottomBar: some View {
        HStack(spacing: 16) {
            Button {
                saveToCameraRoll()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 22))
                    Text("カメラロールへ保存")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(AppTheme.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.primary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                deleteSelected()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 22))
                    Text("削除")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
    }

    // MARK: - Standard Bottom Bar

    private var standardBottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                // Save Destination button (replaces album icon)
                Button {
                    showSaveDestination = true
                } label: {
                    tabBarItem(
                        icon: PrivacySettingsManager.shared.saveDestination.icon,
                        label: "保存方法",
                        isActive: PrivacySettingsManager.shared.saveDestination == .cameraRoll
                    )
                }
                Spacer()
                // Camera shortcut — dismiss entire chain back to CameraView
                Button {
                    if let onDismissToCamera {
                        onDismissToCamera()
                    } else {
                        dismiss()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(AppTheme.primary)
                            .frame(width: 48, height: 48)
                            .shadow(color: AppTheme.primary.opacity(0.3), radius: 8)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                    }
                }
                Spacer()
                // Spacer to balance layout
                Color.clear.frame(width: 48, height: 44)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }

    private func tabBarItem(icon: String, label: String, isActive: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 22))
            Text(label)
                .font(.system(size: 10))
        }
        .foregroundColor(isActive ? AppTheme.primary : .secondary)
    }

    // MARK: - Save Destination

    private func requestCameraRollPermissionAndSet() {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                if status == .authorized || status == .limited {
                    PrivacySettingsManager.shared.saveDestination = .cameraRoll
                } else {
                    showPhotoPermissionDenied = true
                }
            }
        }
    }

    // MARK: - Actions

    private func loadFiles() {
        files = SecureStorage.shared.listFiles()
        // Load thumbnails
        for file in files {
            if let thumb = SecureStorage.shared.loadThumbnail(fileId: file.id) {
                thumbnails[file.id] = thumb
            }
        }
    }

    // MARK: - Storage Warning

    private static let storageWarningThresholdKey = "boxStorageWarningLastThreshold"

    /// Check if file count exceeds thresholds (100, 120, 140, ...) and show a warning popup.
    private func checkStorageWarning() {
        let count = files.count
        guard count >= 100 else { return }

        // Current threshold: 100, 120, 140, ...
        let currentThreshold = 100 + ((count - 100) / 20) * 20
        let lastThreshold = UserDefaults.standard.integer(forKey: Self.storageWarningThresholdKey)

        if currentThreshold > lastThreshold {
            UserDefaults.standard.set(currentThreshold, forKey: Self.storageWarningThresholdKey)
            storageWarningMessage = "BOX内のファイルが\(count)件になりました。\nストレージを節約するため、不要なファイルをカメラロールへ移動するか、削除してください。"
            showStorageWarning = true
        }
    }

    private func toggleSelection(_ id: String) {
        if selectedFiles.contains(id) {
            selectedFiles.remove(id)
        } else {
            selectedFiles.insert(id)
        }
    }

    private func openFile(_ file: SecureStorage.StoredFile) {
        if file.mediaType == .video {
            selectedVideoFile = file
        } else {
            selectedFileForEdit = file
        }
    }

    // MARK: - Drag Selection

    private func handleDragChanged(at location: CGPoint, startLocation: CGPoint) {
        if !isDragSelecting {
            // First call: determine add or remove mode
            isDragSelecting = true
            if let hitId = hitTest(at: startLocation) {
                dragAddMode = !selectedFiles.contains(hitId)
            } else {
                dragAddMode = true
            }
        }

        guard let hitId = hitTest(at: location), hitId != lastDragHitId else { return }
        lastDragHitId = hitId

        if dragAddMode {
            if !selectedFiles.contains(hitId) {
                selectedFiles.insert(hitId)
                AppTheme.selectionFeedback()
            }
        } else {
            if selectedFiles.contains(hitId) {
                selectedFiles.remove(hitId)
                AppTheme.selectionFeedback()
            }
        }
    }

    private func hitTest(at point: CGPoint) -> String? {
        for (id, frame) in cellFrames {
            if frame.contains(point) {
                return id
            }
        }
        return nil
    }

    private func deleteSelected() {
        for id in selectedFiles {
            let file = files.first { $0.id == id }
            if file?.mediaType == .video {
                SecureStorage.shared.deleteVideo(fileId: id)
            } else {
                SecureStorage.shared.deleteImage(fileId: id)
            }
        }
        selectedFiles.removeAll()
        loadFiles()
    }

    // MARK: - Camera Roll Save

    private func saveToCameraRoll() {
        let selectedEntries = files.filter { selectedFiles.contains($0.id) }
        guard !selectedEntries.isEmpty else { return }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                guard status == .authorized || status == .limited else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showSaveError = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        withAnimation { showSaveError = false }
                    }
                    return
                }

                performCameraRollSave(entries: selectedEntries)
            }
        }
    }

    private func performCameraRollSave(entries: [SecureStorage.StoredFile]) {
        PHPhotoLibrary.shared().performChanges {
            for entry in entries {
                if entry.mediaType == .photo {
                    // Use loadImageData() to get raw JPEG with embedded EXIF metadata intact
                    if let data = SecureStorage.shared.loadImageData(fileId: entry.id) {
                        let request = PHAssetCreationRequest.forAsset()
                        request.addResource(with: .photo, data: data, options: nil)
                    }
                } else if entry.mediaType == .video {
                    if let videoURL = SecureStorage.shared.loadVideoURL(fileId: entry.id) {
                        let request = PHAssetCreationRequest.forAsset()
                        let options = PHAssetResourceCreationOptions()
                        options.shouldMoveFile = false
                        request.addResource(with: .video, fileURL: videoURL, options: options)
                    }
                }
            }
        } completionHandler: { success, _ in
            DispatchQueue.main.async {
                if success {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showSaveSuccess = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation { showSaveSuccess = false }
                    }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showSaveError = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        withAnimation { showSaveError = false }
                    }
                }
            }
        }
    }
}

// MARK: - CellFramePreferenceKey

struct CellFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Grid Cell

struct PhotoGridCell: View {
    let file: SecureStorage.StoredFile
    let thumbnail: UIImage?
    let isEditing: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                if let thumb = thumbnail {
                    GeometryReader { geo in
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                    .aspectRatio(1, contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color(.secondarySystemBackground))
                        .aspectRatio(1, contentMode: .fill)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        }
                }

                if file.mediaType == .video {
                    HStack(spacing: 3) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 9))
                        Text(Self.formatDuration(file.duration))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .foregroundColor(.white)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }

                if isEditing {
                    ZStack {
                        Circle()
                            .fill(isSelected ? AppTheme.primary : .clear)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .stroke(isSelected ? AppTheme.primary : .white, lineWidth: 2)
                            )

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? AppTheme.primary : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    static func formatDuration(_ duration: TimeInterval?) -> String {
        guard let d = duration, d.isFinite else { return "0:00" }
        let total = Int(d)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
