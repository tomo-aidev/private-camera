import AVFoundation
import Foundation
import CryptoKit
import UIKit
import os.log

/// Encrypted local storage for captured images.
/// All data is stored in the app's sandboxed container — never written to the system photo library.
final class SecureStorage {

    static let shared = SecureStorage()
    private let logger = Logger(subsystem: "com.privatecamera", category: "SecureStorage")

    /// Root directory for encrypted storage.
    private let storageRoot: URL

    /// Encryption key derived from the user's passcode and stored in Keychain.
    private var encryptionKey: SymmetricKey?

    // MARK: - Init

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageRoot = appSupport.appendingPathComponent("PrivateBox", isDirectory: true)

        // Create directory with NSFileProtectionComplete
        try? FileManager.default.createDirectory(
            at: storageRoot,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )

        // Create subdirectories
        for subdir in ["photos", "videos", "thumbnails"] {
            let url = storageRoot.appendingPathComponent(subdir, isDirectory: true)
            try? FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
    }

    // MARK: - Key Management

    /// Derive encryption key from passcode.
    func deriveKey(from passcode: String) {
        let salt = getOrCreateSalt()
        let passcodeData = Data(passcode.utf8)

        // Use SHA256-based key derivation (HKDF)
        let inputKeyMaterial = SymmetricKey(data: passcodeData)
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKeyMaterial,
            salt: salt,
            info: Data("PrivateCamera.EncryptionKey".utf8),
            outputByteCount: 32
        )

        self.encryptionKey = derivedKey
    }

    private func getOrCreateSalt() -> Data {
        let saltKey = "com.privatecamera.salt"

        // Try to read from Keychain
        if let existingSalt = KeychainHelper.read(key: saltKey) {
            return existingSalt
        }

        // Generate new salt
        var salt = Data(count: 32)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }

        KeychainHelper.save(key: saltKey, data: salt)
        return salt
    }

    // MARK: - Save

    /// Save an image to the encrypted private box.
    /// Returns the file identifier.
    /// - Parameters:
    ///   - image: The captured UIImage.
    ///   - scrubSettings: Which metadata to keep/remove.
    ///   - captureContext: Optional context with location and timestamp for metadata injection.
    @discardableResult
    func saveImage(_ image: UIImage, scrubSettings: ExifScrubber.ScrubSettings = .removeAll, captureContext: ExifScrubber.CaptureContext? = nil) -> String? {
        guard let jpegData = image.jpegData(compressionQuality: 0.95) else {
            logger.error("Failed to create JPEG data")
            return nil
        }

        // Step 1: Scrub all metadata first (start clean)
        guard var processedData = ExifScrubber.scrub(jpegData: jpegData, settings: .removeAll) else {
            logger.error("Failed to scrub EXIF data")
            return nil
        }

        // Step 2: Inject metadata that user wants to KEEP
        let needsInjection = scrubSettings.keepLocation || scrubSettings.keepDateTime || scrubSettings.keepDeviceInfo
        if needsInjection {
            let context = captureContext ?? ExifScrubber.CaptureContext(
                location: scrubSettings.keepLocation ? LocationManager.shared.getLatestCoordinates() : nil,
                captureDate: Date()
            )
            if let injected = ExifScrubber.injectMetadata(into: processedData, settings: scrubSettings, context: context) {
                processedData = injected
            } else {
                logger.warning("Metadata injection failed, saving without metadata")
            }
        }

        let cleanData = processedData

        // Verify result
        let audit = ExifScrubber.verifyClean(data: cleanData)
        if scrubSettings.keepLocation && !audit.hasGPS {
            logger.warning("GPS injection expected but not found in output")
        }
        if scrubSettings.keepDateTime && !audit.hasDateTime {
            logger.warning("DateTime injection expected but not found in output")
        }

        // Generate unique ID
        let fileId = UUID().uuidString
        let filename = "\(fileId).jpg"

        // Encrypt if key is available
        let dataToSave: Data
        if let key = encryptionKey {
            guard let encrypted = encrypt(data: cleanData, key: key) else {
                logger.error("Encryption failed")
                return nil
            }
            dataToSave = encrypted
        } else {
            // Save without additional encryption (still protected by NSFileProtectionComplete)
            dataToSave = cleanData
        }

        // Write to disk
        let fileURL = storageRoot.appendingPathComponent("photos").appendingPathComponent(filename)
        do {
            try dataToSave.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            logger.error("Failed to write file: \(error)")
            return nil
        }

        // Generate and save thumbnail
        saveThumbnail(image: image, fileId: fileId)

        // Save metadata index
        saveMetadataEntry(fileId: fileId, originalSize: cleanData.count, isEncrypted: encryptionKey != nil)

        logger.info("Saved image: \(fileId) (\(cleanData.count) bytes, encrypted: \(self.encryptionKey != nil))")
        return fileId
    }

    /// Save a video file to the encrypted private box.
    /// Uses file-level copy/move to avoid loading the entire video into memory.
    @discardableResult
    func saveVideoFile(from sourceURL: URL) -> String? {
        let fileId = UUID().uuidString
        let filename = "\(fileId).mov"
        let destURL = storageRoot.appendingPathComponent("videos").appendingPathComponent(filename)

        do {
            let fileSize = try FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? Int ?? 0

            if let key = encryptionKey {
                // Read, encrypt, and write (required for AES-GCM authentication tag)
                let videoData = try Data(contentsOf: sourceURL)
                guard let encrypted = encrypt(data: videoData, key: key) else {
                    logger.error("Video encryption failed")
                    return nil
                }
                try encrypted.write(to: destURL, options: [.atomic, .completeFileProtection])
            } else {
                // No encryption key — move file directly (no memory overhead)
                try FileManager.default.moveItem(at: sourceURL, to: destURL)
            }

            // Use the correct URL for reading the unencrypted video
            // (moveItem moves sourceURL → destURL when no encryption; sourceURL still exists when encrypted)
            let readableVideoURL = encryptionKey == nil ? destURL : sourceURL

            // Generate video thumbnail
            saveVideoThumbnail(from: readableVideoURL, fileId: fileId)

            // Extract video duration
            let asset = AVAsset(url: readableVideoURL)
            let duration = CMTimeGetSeconds(asset.duration)

            // Save metadata
            var files = listFiles()
            let entry = StoredFile(
                id: fileId,
                createdAt: Date(),
                sizeBytes: fileSize,
                isEncrypted: encryptionKey != nil,
                mediaType: .video,
                duration: duration.isFinite ? duration : nil
            )
            files.append(entry)
            saveMetadataList(files)

            logger.info("Saved video: \(fileId) (\(fileSize) bytes)")
            return fileId
        } catch {
            logger.error("Failed to save video file: \(error)")
            return nil
        }
    }

    /// Generate a thumbnail from a video file.
    private func saveVideoThumbnail(from videoURL: URL, fileId: String) {
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 300, height: 300)

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
            let thumbnail = UIImage(cgImage: cgImage)
            if let thumbData = thumbnail.jpegData(compressionQuality: 0.7) {
                let url = storageRoot.appendingPathComponent("thumbnails").appendingPathComponent("\(fileId)_thumb.jpg")
                try? thumbData.write(to: url, options: .completeFileProtection)
            }
        }
    }

    // MARK: - Load

    /// Load an image from the private box.
    func loadImage(fileId: String) -> UIImage? {
        let filename = "\(fileId).jpg"
        let fileURL = storageRoot.appendingPathComponent("photos").appendingPathComponent(filename)

        guard let data = try? Data(contentsOf: fileURL) else {
            logger.error("File not found: \(fileId)")
            return nil
        }

        let imageData: Data
        if let key = encryptionKey {
            guard let decrypted = decrypt(data: data, key: key) else {
                // Try without decryption (might be unencrypted)
                imageData = data
                return UIImage(data: imageData)
            }
            imageData = decrypted
        } else {
            imageData = data
        }

        return UIImage(data: imageData)
    }

    /// Get the playable URL for a video file.
    /// For unencrypted videos, returns the storage URL directly.
    /// For encrypted videos, decrypts to a temp file and returns the temp URL.
    func loadVideoURL(fileId: String) -> URL? {
        let filename = "\(fileId).mov"
        let fileURL = storageRoot.appendingPathComponent("videos").appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.error("Video file not found: \(fileId)")
            return nil
        }

        if let key = encryptionKey {
            // Encrypted — decrypt to temp file for playback
            guard let data = try? Data(contentsOf: fileURL),
                  let decrypted = decrypt(data: data, key: key) else {
                // Try as unencrypted
                return fileURL
            }
            let tempDir = FileManager.default.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent("playback_\(fileId).mov")
            do {
                try decrypted.write(to: tempURL)
                return tempURL
            } catch {
                logger.error("Failed to write decrypted video: \(error)")
                return nil
            }
        } else {
            return fileURL
        }
    }

    /// Get the raw file URL for a video (for camera roll export).
    func videoFileURL(fileId: String) -> URL? {
        let filename = "\(fileId).mov"
        let fileURL = storageRoot.appendingPathComponent("videos").appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL
    }

    /// Load raw JPEG data from the private box (preserves embedded EXIF metadata).
    /// Use this instead of loadImage() when you need metadata-intact data
    /// (e.g., exporting to Camera Roll).
    func loadImageData(fileId: String) -> Data? {
        let filename = "\(fileId).jpg"
        let fileURL = storageRoot.appendingPathComponent("photos").appendingPathComponent(filename)

        guard let data = try? Data(contentsOf: fileURL) else {
            logger.error("File not found: \(fileId)")
            return nil
        }

        if let key = encryptionKey {
            guard let decrypted = decrypt(data: data, key: key) else {
                // Try without decryption (might be unencrypted)
                return data
            }
            return decrypted
        } else {
            return data
        }
    }

    /// Load a thumbnail.
    func loadThumbnail(fileId: String) -> UIImage? {
        let url = storageRoot.appendingPathComponent("thumbnails").appendingPathComponent("\(fileId)_thumb.jpg")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// List all saved file IDs.
    func listFiles() -> [StoredFile] {
        let metadataURL = storageRoot.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metadataURL),
              let entries = try? JSONDecoder().decode([StoredFile].self, from: data) else {
            return []
        }
        return entries.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Delete

    func deleteImage(fileId: String) {
        let photoURL = storageRoot.appendingPathComponent("photos").appendingPathComponent("\(fileId).jpg")
        let thumbURL = storageRoot.appendingPathComponent("thumbnails").appendingPathComponent("\(fileId)_thumb.jpg")

        try? FileManager.default.removeItem(at: photoURL)
        try? FileManager.default.removeItem(at: thumbURL)

        var files = listFiles()
        files.removeAll { $0.id == fileId }
        saveMetadataList(files)

        logger.info("Deleted photo: \(fileId)")
    }

    func deleteVideo(fileId: String) {
        let videoURL = storageRoot.appendingPathComponent("videos").appendingPathComponent("\(fileId).mov")
        let thumbURL = storageRoot.appendingPathComponent("thumbnails").appendingPathComponent("\(fileId)_thumb.jpg")

        try? FileManager.default.removeItem(at: videoURL)
        try? FileManager.default.removeItem(at: thumbURL)

        var files = listFiles()
        files.removeAll { $0.id == fileId }
        saveMetadataList(files)

        logger.info("Deleted video: \(fileId)")
    }

    // MARK: - Encryption

    private func encrypt(data: Data, key: SymmetricKey) -> Data? {
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            return sealedBox.combined
        } catch {
            logger.error("Encryption error: \(error)")
            return nil
        }
    }

    private func decrypt(data: Data, key: SymmetricKey) -> Data? {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            logger.error("Decryption error: \(error)")
            return nil
        }
    }

    // MARK: - Thumbnail

    private func saveThumbnail(image: UIImage, fileId: String) {
        let thumbSize = CGSize(width: 300, height: 300)
        let renderer = UIGraphicsImageRenderer(size: thumbSize)
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: thumbSize))
        }

        if let thumbData = thumbnail.jpegData(compressionQuality: 0.7) {
            let url = storageRoot.appendingPathComponent("thumbnails").appendingPathComponent("\(fileId)_thumb.jpg")
            try? thumbData.write(to: url, options: .completeFileProtection)
        }
    }

    // MARK: - Metadata Index

    struct StoredFile: Codable, Identifiable {
        let id: String
        let createdAt: Date
        let sizeBytes: Int
        let isEncrypted: Bool
        let mediaType: MediaType
        var duration: TimeInterval?

        enum MediaType: String, Codable {
            case photo, video
        }
    }

    private func saveMetadataEntry(fileId: String, originalSize: Int, isEncrypted: Bool) {
        var files = listFiles()
        let entry = StoredFile(
            id: fileId,
            createdAt: Date(),
            sizeBytes: originalSize,
            isEncrypted: isEncrypted,
            mediaType: .photo
        )
        files.append(entry)
        saveMetadataList(files)
    }

    private func saveMetadataList(_ files: [StoredFile]) {
        let metadataURL = storageRoot.appendingPathComponent("metadata.json")
        if let data = try? JSONEncoder().encode(files) {
            try? data.write(to: metadataURL, options: .completeFileProtection)
        }
    }
}

// MARK: - Keychain Helper

enum KeychainHelper {
    static func save(key: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
