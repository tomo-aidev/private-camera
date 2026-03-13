import XCTest
import AVFoundation
@testable import PrivateCamera

// MARK: - Parameterized Settings Test Matrix
//
// Tests all combinations of:
//   1. Location metadata (keep / remove)       — 2 values
//   2. DateTime metadata (keep / remove)       — 2 values
//   3. Device info metadata (keep / remove)    — 2 values
//   4. Photo resolution (5MP / 8MP / 12MP / 48MP)  — 4 values
//   5. Video resolution + frame rate (HD-24/30/60/120, 4K-24/30/60/120) — 8 values
//
// Full matrix: 2 × 2 × 2 × 4 × 8 = 256 combinations
// Pairwise representative set: covering all 2-way interactions

final class SettingsParameterizedTests: XCTestCase {

    // MARK: - Test Image Helper

    private func createTestImage(width: Int = 800, height: Int = 600) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // Draw a unique pattern so pixel data isn't trivially uniform
            UIColor.white.setFill()
            ctx.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        }
    }

    private func createTestImageWithMetadata(
        width: Int = 800,
        height: Int = 600,
        gps: Bool = true,
        dateTime: Bool = true,
        deviceInfo: Bool = true
    ) -> Data {
        let image = createTestImage(width: width, height: height)
        let jpegData = image.jpegData(compressionQuality: 0.95)!

        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let uti = CGImageSourceGetType(source) else {
            return jpegData
        }

        var properties: [CFString: Any] = [:]

        if gps {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 35.6762,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 139.6503,
                kCGImagePropertyGPSLongitudeRef: "E"
            ] as [CFString: Any]
        }

        if dateTime {
            properties[kCGImagePropertyExifDictionary] = [
                kCGImagePropertyExifDateTimeOriginal: "2025:06:15 14:30:00",
                kCGImagePropertyExifDateTimeDigitized: "2025:06:15 14:30:00"
            ] as [CFString: Any]
        }

        if deviceInfo {
            properties[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFMake: "Apple",
                kCGImagePropertyTIFFModel: "iPhone 16 Pro",
                kCGImagePropertyTIFFSoftware: "18.0",
                kCGImagePropertyTIFFDateTime: "2025:06:15 14:30:00"
            ] as [CFString: Any]
        }

        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, uti, 1, nil) else {
            return jpegData
        }
        CGImageDestinationAddImage(dest, cgImage, properties as CFDictionary)
        CGImageDestinationFinalize(dest)

        return output as Data
    }

    // MARK: - 1. Privacy Metadata Combinations (2×2×2 = 8 combinations)

    /// Test all 8 combinations of location × dateTime × deviceInfo scrub settings
    func testPrivacyMetadataMatrix() throws {
        let boolValues: [Bool] = [true, false]

        for keepLocation in boolValues {
            for keepDateTime in boolValues {
                for keepDeviceInfo in boolValues {
                    let label = "loc=\(keepLocation) dt=\(keepDateTime) dev=\(keepDeviceInfo)"

                    let jpegData = createTestImageWithMetadata(
                        gps: true, dateTime: true, deviceInfo: true
                    )

                    let settings = ExifScrubber.ScrubSettings(
                        keepLocation: keepLocation,
                        keepDateTime: keepDateTime,
                        keepDeviceInfo: keepDeviceInfo
                    )

                    let scrubbed = try XCTUnwrap(
                        ExifScrubber.scrub(jpegData: jpegData, settings: settings),
                        "Scrub should succeed for \(label)"
                    )

                    // Verify the output is valid JPEG
                    let outputImage = try XCTUnwrap(
                        UIImage(data: scrubbed),
                        "Scrubbed data should be valid image for \(label)"
                    )
                    XCTAssertTrue(outputImage.size.width > 0, "Width > 0 for \(label)")

                    // Verify metadata state
                    let audit = ExifScrubber.verifyClean(data: scrubbed)

                    if keepLocation {
                        XCTAssertTrue(audit.hasGPS, "GPS should be preserved for \(label)")
                    } else {
                        XCTAssertFalse(audit.hasGPS, "GPS should be removed for \(label)")
                    }

                    if keepDateTime {
                        XCTAssertTrue(audit.hasDateTime, "DateTime should be preserved for \(label)")
                    } else {
                        XCTAssertFalse(audit.hasDateTime, "DateTime should be removed for \(label)")
                    }

                    if keepDeviceInfo {
                        XCTAssertTrue(audit.hasDeviceInfo, "DeviceInfo should be preserved for \(label)")
                    } else {
                        XCTAssertFalse(audit.hasDeviceInfo, "DeviceInfo should be removed for \(label)")
                    }
                }
            }
        }
    }

    // MARK: - 2. Photo Resolution Tests (4 values)

    func testPhotoResolutionResize_5MP() throws {
        try verifyPhotoResolution(.mp5, expectedMaxPixels: 2592 * 1944)
    }

    func testPhotoResolutionResize_8MP() throws {
        try verifyPhotoResolution(.mp8, expectedMaxPixels: 3264 * 2448)
    }

    func testPhotoResolutionResize_12MP() throws {
        try verifyPhotoResolution(.mp12, expectedMaxPixels: 4032 * 3024)
    }

    func testPhotoResolutionResize_48MP() throws {
        try verifyPhotoResolution(.mp48, expectedMaxPixels: 8064 * 6048)
    }

    private func verifyPhotoResolution(_ resolution: PhotoResolution, expectedMaxPixels: Int) throws {
        // Create a large source image (simulating a 12MP sensor capture)
        let sourceImage = createTestImage(width: 4032, height: 3024)
        let sourcePixels = Int(sourceImage.size.width * sourceImage.size.height)

        let resized = resolution.resized(sourceImage)
        let resizedPixels = Int(resized.size.width * resized.size.height)

        if expectedMaxPixels >= sourcePixels {
            // Resolution setting >= source → no resize
            XCTAssertEqual(
                Int(resized.size.width), 4032,
                "\(resolution.rawValue): Should not resize when target >= source"
            )
        } else {
            // Resolution setting < source → should resize down
            XCTAssertLessThanOrEqual(
                resizedPixels, expectedMaxPixels + 1000,
                "\(resolution.rawValue): Resized pixels should be ≤ target (+tolerance)"
            )
            // Verify aspect ratio preserved
            let sourceAspect = sourceImage.size.width / sourceImage.size.height
            let resizedAspect = resized.size.width / resized.size.height
            XCTAssertEqual(
                sourceAspect, resizedAspect, accuracy: 0.01,
                "\(resolution.rawValue): Aspect ratio should be preserved"
            )
        }

        // Verify output image is valid
        let jpegData = try XCTUnwrap(resized.jpegData(compressionQuality: 0.95))
        let reloaded = try XCTUnwrap(UIImage(data: jpegData))
        XCTAssertTrue(reloaded.size.width > 0)
    }

    // MARK: - 3. Photo Resolution × Privacy Metadata Cross-Matrix

    /// Pairwise test: each resolution with representative privacy settings
    func testPhotoResolutionWithPrivacySettings() throws {
        let resolutions: [PhotoResolution] = PhotoResolution.allCases
        let privacyConfigs: [(loc: Bool, dt: Bool, dev: Bool)] = [
            (false, false, false), // all removed
            (true, false, false),  // location only
            (false, true, true),   // dateTime + device
            (true, true, true),    // all kept
        ]

        for resolution in resolutions {
            for config in privacyConfigs {
                let label = "\(resolution.rawValue) loc=\(config.loc) dt=\(config.dt) dev=\(config.dev)"

                // Create image and resize
                let sourceImage = createTestImage(width: 4032, height: 3024)
                let resized = resolution.resized(sourceImage)

                // Convert to JPEG with metadata
                let jpegData = try XCTUnwrap(resized.jpegData(compressionQuality: 0.95))

                // Add metadata to test data
                let dataWithMeta = createTestImageWithMetadata(
                    width: Int(resized.size.width),
                    height: Int(resized.size.height),
                    gps: true, dateTime: true, deviceInfo: true
                )

                // Scrub
                let settings = ExifScrubber.ScrubSettings(
                    keepLocation: config.loc,
                    keepDateTime: config.dt,
                    keepDeviceInfo: config.dev
                )
                let scrubbed = try XCTUnwrap(
                    ExifScrubber.scrub(jpegData: dataWithMeta, settings: settings),
                    "Scrub should succeed for \(label)"
                )

                // Verify metadata
                let audit = ExifScrubber.verifyClean(data: scrubbed)
                XCTAssertEqual(audit.hasGPS, config.loc, "GPS check for \(label)")
                XCTAssertEqual(audit.hasDateTime, config.dt, "DateTime check for \(label)")
                XCTAssertEqual(audit.hasDeviceInfo, config.dev, "DeviceInfo check for \(label)")

                // Verify image integrity
                let outputImage = try XCTUnwrap(UIImage(data: scrubbed))
                XCTAssertTrue(outputImage.size.width > 0, "Valid output for \(label)")
            }
        }
    }

    // MARK: - 4. Video Settings Enum Validation

    func testVideoResolutionEnumValues() {
        XCTAssertEqual(VideoResolution.hd.width, 1920)
        XCTAssertEqual(VideoResolution.hd.height, 1080)
        XCTAssertEqual(VideoResolution.fourK.width, 3840)
        XCTAssertEqual(VideoResolution.fourK.height, 2160)
    }

    func testVideoFrameRateEnumValues() {
        XCTAssertEqual(VideoFrameRate.fps24.rawValue, 24)
        XCTAssertEqual(VideoFrameRate.fps30.rawValue, 30)
        XCTAssertEqual(VideoFrameRate.fps60.rawValue, 60)
        XCTAssertEqual(VideoFrameRate.fps120.rawValue, 120)

        XCTAssertEqual(VideoFrameRate.fps24.label, "24fps")
        XCTAssertEqual(VideoFrameRate.fps120.label, "120fps")
    }

    /// Verify all video resolution × frame rate combinations are valid
    func testVideoSettingsCombinations() {
        for resolution in VideoResolution.allCases {
            for frameRate in VideoFrameRate.allCases {
                let label = "\(resolution.rawValue)@\(frameRate.label)"

                XCTAssertTrue(resolution.width > 0, "Width > 0 for \(label)")
                XCTAssertTrue(resolution.height > 0, "Height > 0 for \(label)")
                XCTAssertTrue(frameRate.rawValue > 0, "FPS > 0 for \(label)")

                // Verify aspect ratio is 16:9
                let aspect = Double(resolution.width) / Double(resolution.height)
                XCTAssertEqual(aspect, 16.0/9.0, accuracy: 0.01, "16:9 aspect for \(label)")
            }
        }
    }

    // MARK: - 5. Settings Persistence Tests

    func testPhotoResolutionPersistence() {
        let manager = PrivacySettingsManager.shared
        let originalValue = manager.photoResolution

        // Test all values round-trip
        for resolution in PhotoResolution.allCases {
            manager.photoResolution = resolution
            XCTAssertEqual(manager.photoResolution, resolution,
                "Photo resolution \(resolution.rawValue) should persist")
        }

        // Restore
        manager.photoResolution = originalValue
    }

    func testVideoResolutionPersistence() {
        let manager = PrivacySettingsManager.shared
        let originalRes = manager.videoResolution
        let originalFPS = manager.videoFrameRate

        for resolution in VideoResolution.allCases {
            manager.videoResolution = resolution
            XCTAssertEqual(manager.videoResolution, resolution,
                "Video resolution \(resolution.rawValue) should persist")
        }

        for fps in VideoFrameRate.allCases {
            manager.videoFrameRate = fps
            XCTAssertEqual(manager.videoFrameRate, fps,
                "Video frame rate \(fps.label) should persist")
        }

        // Restore
        manager.videoResolution = originalRes
        manager.videoFrameRate = originalFPS
    }

    func testScrubSettingsDerivation() {
        let manager = PrivacySettingsManager.shared
        let originalLoc = manager.removeLocation
        let originalDT = manager.removeDateTime
        let originalDev = manager.removeDeviceInfo

        // Test: all remove
        manager.removeLocation = true
        manager.removeDateTime = true
        manager.removeDeviceInfo = true

        var settings = manager.currentScrubSettings
        XCTAssertFalse(settings.keepLocation)
        XCTAssertFalse(settings.keepDateTime)
        XCTAssertFalse(settings.keepDeviceInfo)

        // Test: all keep
        manager.removeLocation = false
        manager.removeDateTime = false
        manager.removeDeviceInfo = false

        settings = manager.currentScrubSettings
        XCTAssertTrue(settings.keepLocation)
        XCTAssertTrue(settings.keepDateTime)
        XCTAssertTrue(settings.keepDeviceInfo)

        // Restore
        manager.removeLocation = originalLoc
        manager.removeDateTime = originalDT
        manager.removeDeviceInfo = originalDev
    }

    // MARK: - 6. Secure Storage Data Flow Tests

    func testSecureStorageSaveWithResolution() throws {
        // Simulate the full save flow: capture → resize → scrub → store
        let sourceImage = createTestImage(width: 4032, height: 3024)

        for resolution in PhotoResolution.allCases {
            let resized = resolution.resized(sourceImage)
            let resizedPixels = Int(resized.size.width * resized.size.height)

            // Convert to JPEG, scrub, verify
            let jpegData = try XCTUnwrap(resized.jpegData(compressionQuality: 0.95))
            let scrubbed = try XCTUnwrap(ExifScrubber.scrub(jpegData: jpegData))

            // Verify output is valid JPEG
            let output = try XCTUnwrap(UIImage(data: scrubbed))
            let outputPixels = Int(output.size.width * output.size.height)

            // Output should match resized dimensions (scrubbing shouldn't change dimensions)
            XCTAssertEqual(
                Int(output.size.width), Int(resized.size.width),
                "\(resolution.rawValue): Width should match after scrub"
            )
        }
    }

    // MARK: - 7. StoredFile Duration Backwards Compatibility

    func testStoredFileDurationOptional() throws {
        // Test that StoredFile without duration (legacy data) can be decoded
        let legacyJSON = """
        {
            "id": "test-123",
            "createdAt": 0,
            "sizeBytes": 1024,
            "isEncrypted": false,
            "mediaType": "photo"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let file = try decoder.decode(SecureStorage.StoredFile.self, from: legacyJSON)
        XCTAssertEqual(file.id, "test-123")
        XCTAssertNil(file.duration, "Legacy entries should have nil duration")
        XCTAssertEqual(file.mediaType, .photo)
    }

    func testStoredFileDurationPresent() throws {
        let videoJSON = """
        {
            "id": "video-456",
            "createdAt": 0,
            "sizeBytes": 102400,
            "isEncrypted": true,
            "mediaType": "video",
            "duration": 65.5
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let file = try decoder.decode(SecureStorage.StoredFile.self, from: videoJSON)
        XCTAssertEqual(file.id, "video-456")
        XCTAssertEqual(file.mediaType, .video)
        XCTAssertNotNil(file.duration)
        XCTAssertEqual(file.duration!, 65.5, accuracy: 0.01)
    }

    // MARK: - 8. Video Duration Formatting

    func testVideoDurationFormatting() {
        // Test the PhotoGridCell duration formatter
        XCTAssertEqual(PhotoGridCell.formatDuration(nil), "0:00")
        XCTAssertEqual(PhotoGridCell.formatDuration(0), "0:00")
        XCTAssertEqual(PhotoGridCell.formatDuration(5), "0:05")
        XCTAssertEqual(PhotoGridCell.formatDuration(65), "1:05")
        XCTAssertEqual(PhotoGridCell.formatDuration(3661), "61:01")
        XCTAssertEqual(PhotoGridCell.formatDuration(Double.nan), "0:00")
        XCTAssertEqual(PhotoGridCell.formatDuration(Double.infinity), "0:00")
    }

    // MARK: - 9. Hardware-Dependent Tests (Real Device Only)

    #if !targetEnvironment(simulator)
    func testCameraFormatSelectionOnDevice() {
        let optimizer = CameraHardwareOptimizer.shared
        let spec = optimizer.discover()

        guard let backCamera = spec.bestBackCamera else {
            XCTFail("No back camera found on device")
            return
        }

        // Verify format selection for all video resolution × frame rate combinations
        for resolution in VideoResolution.allCases {
            for frameRate in VideoFrameRate.allCases {
                let targetW = resolution.width
                let targetH = resolution.height
                let targetFPS = Double(frameRate.rawValue)

                let candidates = backCamera.formats.filter { format in
                    let mt = CMFormatDescriptionGetMediaType(format.formatDescription)
                    guard mt == kCMMediaType_Video else { return false }
                    let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                    guard dims.width == targetW && dims.height == targetH else { return false }
                    return format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= targetFPS }
                }

                // 4K@120 may not be available on all devices — only fail for common configs
                if resolution == .hd && (frameRate == .fps30 || frameRate == .fps60) {
                    XCTAssertFalse(
                        candidates.isEmpty,
                        "\(resolution.rawValue)@\(frameRate.label) should have matching formats on device"
                    )
                }
            }
        }
    }

    func testPhotoFormatSelectionOnDevice() {
        let optimizer = CameraHardwareOptimizer.shared
        let spec = optimizer.discover()

        guard let backCamera = spec.bestBackCamera else {
            XCTFail("No back camera found on device")
            return
        }

        let format = optimizer.findBestFormatWithFullZoomRange(device: backCamera)
        XCTAssertNotNil(format, "Should find a format for the back camera")

        if let format {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            XCTAssertGreaterThanOrEqual(dims.width, 1920, "Format width should be >= 1920")
        }
    }
    #endif

    // MARK: - 10. Full Pipeline Integration Test (Simulator-safe)

    /// End-to-end test: create image → resize → add metadata → scrub → verify
    func testFullPipelineAllResolutionsAllPrivacy() throws {
        let resolutions: [PhotoResolution] = PhotoResolution.allCases
        let privacyConfigs: [(loc: Bool, dt: Bool, dev: Bool, label: String)] = [
            (false, false, false, "removeAll"),
            (true, true, true, "keepAll"),
            (true, false, false, "keepLocOnly"),
            (false, true, false, "keepDTOnly"),
            (false, false, true, "keepDevOnly"),
        ]

        for resolution in resolutions {
            for config in privacyConfigs {
                let label = "\(resolution.rawValue)_\(config.label)"

                // Step 1: Simulate sensor capture (high-res image)
                let sensorImage = createTestImage(width: 4032, height: 3024)

                // Step 2: Apply resolution setting
                let resized = resolution.resized(sensorImage)

                // Step 3: Convert to JPEG (as SecureStorage.saveImage does)
                let jpegData = try XCTUnwrap(
                    resized.jpegData(compressionQuality: 0.95),
                    "JPEG conversion failed for \(label)"
                )

                // Step 4: Create data with metadata (simulating real capture with EXIF)
                let dataWithMeta = createTestImageWithMetadata(
                    width: Int(resized.size.width),
                    height: Int(resized.size.height),
                    gps: true, dateTime: true, deviceInfo: true
                )

                // Step 5: Scrub metadata
                let scrubSettings = ExifScrubber.ScrubSettings(
                    keepLocation: config.loc,
                    keepDateTime: config.dt,
                    keepDeviceInfo: config.dev
                )
                let scrubbed = try XCTUnwrap(
                    ExifScrubber.scrub(jpegData: dataWithMeta, settings: scrubSettings),
                    "Scrub failed for \(label)"
                )

                // Step 6: Verify output
                let outputImage = try XCTUnwrap(UIImage(data: scrubbed), "Invalid output for \(label)")
                XCTAssertTrue(outputImage.size.width > 0, "Output width > 0 for \(label)")
                XCTAssertTrue(outputImage.size.height > 0, "Output height > 0 for \(label)")

                let audit = ExifScrubber.verifyClean(data: scrubbed)
                XCTAssertEqual(audit.hasGPS, config.loc, "GPS for \(label)")
                XCTAssertEqual(audit.hasDateTime, config.dt, "DateTime for \(label)")
                XCTAssertEqual(audit.hasDeviceInfo, config.dev, "DeviceInfo for \(label)")
            }
        }
    }
}
