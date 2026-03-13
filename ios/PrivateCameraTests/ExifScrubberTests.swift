import XCTest
@testable import PrivateCamera

final class ExifScrubberTests: XCTestCase {

    // MARK: - Test: Scrub removes GPS data

    func testScrubRemovesGPS() throws {
        // Create a test image with GPS metadata
        let image = createTestImage()
        let jpegData = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))

        // Add GPS metadata to the JPEG
        let dataWithGPS = addGPSMetadata(to: jpegData)

        // Verify GPS exists before scrub
        let auditBefore = ExifScrubber.verifyClean(data: dataWithGPS)
        XCTAssertTrue(auditBefore.hasGPS, "Test image should have GPS before scrub")

        // Scrub
        let scrubbed = try XCTUnwrap(ExifScrubber.scrub(jpegData: dataWithGPS))

        // Verify GPS is removed
        let auditAfter = ExifScrubber.verifyClean(data: scrubbed)
        XCTAssertFalse(auditAfter.hasGPS, "Scrubbed image should not have GPS")
    }

    // MARK: - Test: Scrub removes DateTime

    func testScrubRemovesDateTime() throws {
        let image = createTestImage()
        let jpegData = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        let dataWithMeta = addFullMetadata(to: jpegData)

        let scrubbed = try XCTUnwrap(ExifScrubber.scrub(jpegData: dataWithMeta))

        let audit = ExifScrubber.verifyClean(data: scrubbed)
        XCTAssertFalse(audit.hasDateTime, "Scrubbed image should not have DateTime")
    }

    // MARK: - Test: Scrub removes device info

    func testScrubRemovesDeviceInfo() throws {
        let image = createTestImage()
        let jpegData = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        let dataWithMeta = addFullMetadata(to: jpegData)

        let scrubbed = try XCTUnwrap(ExifScrubber.scrub(jpegData: dataWithMeta))

        let audit = ExifScrubber.verifyClean(data: scrubbed)
        XCTAssertFalse(audit.hasDeviceInfo, "Scrubbed image should not have device info")
    }

    // MARK: - Test: Full scrub produces clean output

    func testFullScrubProducesCleanOutput() throws {
        let image = createTestImage()
        let jpegData = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        let dataWithMeta = addFullMetadata(to: jpegData)

        let scrubbed = try XCTUnwrap(ExifScrubber.scrub(jpegData: dataWithMeta))

        let audit = ExifScrubber.verifyClean(data: scrubbed)
        XCTAssertTrue(audit.isFullyClean, "Fully scrubbed image should have no identifying metadata")
    }

    // MARK: - Test: Selective keep preserves chosen metadata

    func testSelectiveKeepLocation() throws {
        let image = createTestImage()
        let jpegData = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        let dataWithMeta = addFullMetadata(to: jpegData)

        let settings = ExifScrubber.ScrubSettings(keepLocation: true, keepDateTime: false, keepDeviceInfo: false)
        let scrubbed = try XCTUnwrap(ExifScrubber.scrub(jpegData: dataWithMeta, settings: settings))

        let audit = ExifScrubber.verifyClean(data: scrubbed)
        XCTAssertTrue(audit.hasGPS, "Should keep GPS when requested")
        XCTAssertFalse(audit.hasDateTime, "Should still remove DateTime")
        XCTAssertFalse(audit.hasDeviceInfo, "Should still remove device info")
    }

    // MARK: - Test: Image quality preserved

    func testImageQualityPreserved() throws {
        let image = createTestImage(width: 4000, height: 3000)
        let jpegData = try XCTUnwrap(image.jpegData(compressionQuality: 0.95))

        let scrubbed = try XCTUnwrap(ExifScrubber.scrub(jpegData: jpegData))

        // Verify we can still create an image from scrubbed data
        let scrubbedImage = try XCTUnwrap(UIImage(data: scrubbed))
        // UIImage.size is in points; on Retina simulators it may differ from pixel dimensions
        // Use CGImage dimensions instead for accurate pixel comparison
        let scrubbedCG = try XCTUnwrap(scrubbedImage.cgImage)
        XCTAssertEqual(scrubbedCG.width, 4000, "Pixel width should be preserved")
        XCTAssertEqual(scrubbedCG.height, 3000, "Pixel height should be preserved")
    }

    // MARK: - Test: verifyNoGPS helper

    func testVerifyNoGPS() throws {
        let image = createTestImage()
        let cleanJPEG = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        XCTAssertTrue(ExifScrubber.verifyNoGPS(in: cleanJPEG))

        let withGPS = addGPSMetadata(to: cleanJPEG)
        XCTAssertFalse(ExifScrubber.verifyNoGPS(in: withGPS))
    }

    // MARK: - Helpers

    private func createTestImage(width: Int = 100, height: Int = 100) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func addGPSMetadata(to jpegData: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let uti = CGImageSourceGetType(source) else {
            return jpegData
        }

        let gpsInfo: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 35.6762,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 139.6503,
            kCGImagePropertyGPSLongitudeRef: "E"
        ]

        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: gpsInfo
        ]

        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, uti, 1, nil) else {
            return jpegData
        }
        CGImageDestinationAddImage(dest, cgImage, properties as CFDictionary)
        CGImageDestinationFinalize(dest)

        return output as Data
    }

    private func addFullMetadata(to jpegData: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let uti = CGImageSourceGetType(source) else {
            return jpegData
        }

        let gpsInfo: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 35.6762,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 139.6503,
            kCGImagePropertyGPSLongitudeRef: "E"
        ]

        let exifInfo: [CFString: Any] = [
            kCGImagePropertyExifDateTimeOriginal: "2025:01:15 14:30:00",
            kCGImagePropertyExifDateTimeDigitized: "2025:01:15 14:30:00"
        ]

        let tiffInfo: [CFString: Any] = [
            kCGImagePropertyTIFFMake: "Apple",
            kCGImagePropertyTIFFModel: "iPhone 16 Pro",
            kCGImagePropertyTIFFSoftware: "17.2",
            kCGImagePropertyTIFFDateTime: "2025:01:15 14:30:00"
        ]

        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: gpsInfo,
            kCGImagePropertyExifDictionary: exifInfo,
            kCGImagePropertyTIFFDictionary: tiffInfo
        ]

        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, uti, 1, nil) else {
            return jpegData
        }
        CGImageDestinationAddImage(dest, cgImage, properties as CFDictionary)
        CGImageDestinationFinalize(dest)

        return output as Data
    }
}
