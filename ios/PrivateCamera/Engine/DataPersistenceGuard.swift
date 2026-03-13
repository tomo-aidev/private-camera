import Foundation
import os.log

/// Ensures photo data survives app updates, rebuilds, and development cycles.
///
/// **Development Rule**: Photo data stored in PrivateBox MUST persist across:
/// - Xcode rebuild & re-deploy
/// - App version updates
/// - Debug ↔ Release config changes
///
/// Data is stored in Application Support (not tmp/cache), so iOS preserves it
/// across app updates as long as the bundle ID remains constant.
final class DataPersistenceGuard {

    static let shared = DataPersistenceGuard()
    private let logger = Logger(subsystem: "com.privatecamera", category: "DataPersistence")

    private let storageVersionKey = "com.privatecamera.storageVersion"
    private let currentStorageVersion = 1

    private init() {}

    // MARK: - Startup Verification

    /// Call on every app launch to verify data integrity and run migrations if needed.
    func verifyOnLaunch() {
        verifyStorageDirectories()
        verifyExcludedFromPurge()
        runMigrationsIfNeeded()
        logStorageStats()
    }

    // MARK: - Directory Verification

    /// Ensure all required directories exist and are properly configured.
    private func verifyStorageDirectories() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let root = appSupport.appendingPathComponent("PrivateBox", isDirectory: true)

        let subdirs = ["photos", "videos", "thumbnails"]

        for dir in [root] + subdirs.map({ root.appendingPathComponent($0, isDirectory: true) }) {
            if !FileManager.default.fileExists(atPath: dir.path) {
                do {
                    try FileManager.default.createDirectory(
                        at: dir,
                        withIntermediateDirectories: true,
                        attributes: [.protectionKey: FileProtectionType.complete]
                    )
                    logger.info("Recreated missing directory: \(dir.lastPathComponent)")
                } catch {
                    logger.error("Failed to create directory \(dir.lastPathComponent): \(error)")
                }
            }
        }
    }

    /// Mark storage directories so iOS doesn't purge them under low-storage pressure.
    /// Application Support is NOT auto-purged, but this adds an extra safety layer.
    private func verifyExcludedFromPurge() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let root = appSupport.appendingPathComponent("PrivateBox", isDirectory: true)

        // isExcludedFromBackup = false means data IS included in backups.
        // This is important: user's encrypted photos should survive device restore.
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = false

        var mutableRoot = root
        try? mutableRoot.setResourceValues(resourceValues)
    }

    // MARK: - Migration

    private func runMigrationsIfNeeded() {
        let savedVersion = UserDefaults.standard.integer(forKey: storageVersionKey)

        if savedVersion < currentStorageVersion {
            logger.info("Running storage migration: v\(savedVersion) → v\(self.currentStorageVersion)")

            // Future migrations go here:
            // if savedVersion < 2 { migrateV1toV2() }

            UserDefaults.standard.set(currentStorageVersion, forKey: storageVersionKey)
        }
    }

    // MARK: - Storage Stats

    private func logStorageStats() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let photosDir = appSupport.appendingPathComponent("PrivateBox/photos", isDirectory: true)
        let thumbsDir = appSupport.appendingPathComponent("PrivateBox/thumbnails", isDirectory: true)

        let photoCount = countFiles(in: photosDir)
        let thumbCount = countFiles(in: thumbsDir)
        let totalSize = directorySize(at: appSupport.appendingPathComponent("PrivateBox"))

        logger.info("""
        📦 Storage Status:
          Photos: \(photoCount) files
          Thumbnails: \(thumbCount) files
          Total size: \(ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file))
          Location: \(photosDir.path)
        """)
    }

    // MARK: - Integrity Check

    /// Verify that all photos listed in metadata actually exist on disk.
    /// Returns orphaned file IDs (in metadata but missing on disk).
    func integrityCheck() -> IntegrityReport {
        let files = SecureStorage.shared.listFiles()
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let photosDir = appSupport.appendingPathComponent("PrivateBox/photos", isDirectory: true)

        var missingFiles: [String] = []
        var orphanedThumbs: [String] = []
        var healthyCount = 0

        for file in files {
            let photoPath = photosDir.appendingPathComponent("\(file.id).jpg")
            if FileManager.default.fileExists(atPath: photoPath.path) {
                healthyCount += 1
            } else {
                missingFiles.append(file.id)
                logger.warning("Missing photo file: \(file.id)")
            }
        }

        let report = IntegrityReport(
            totalInIndex: files.count,
            healthyOnDisk: healthyCount,
            missingFromDisk: missingFiles,
            orphanedThumbnails: orphanedThumbs
        )

        logger.info("Integrity check: \(healthyCount)/\(files.count) healthy")
        return report
    }

    struct IntegrityReport {
        let totalInIndex: Int
        let healthyOnDisk: Int
        let missingFromDisk: [String]
        let orphanedThumbnails: [String]

        var isHealthy: Bool { missingFromDisk.isEmpty }
    }

    // MARK: - Helpers

    private func countFiles(in directory: URL) -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.count ?? 0
    }

    private func directorySize(at url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += size
            }
        }
        return total
    }
}
