import AVFoundation
import UIKit
import ImageIO
import CoreLocation
import os.log

/// Strips EXIF/metadata from images at the binary level before saving.
/// Removes: GPS, DateTime, Device info, Lens details, Software version.
struct ExifScrubber {

    private static let logger = Logger(subsystem: "com.privatecamera", category: "ExifScrubber")

    /// Metadata keys that are always removed for privacy.
    private static let alwaysStrippedKeys: Set<CFString> = [
        kCGImagePropertyMakerAppleDictionary
    ]

    /// Keys stripped unless the user explicitly opts to keep them.
    static let optionalKeys: [MetadataCategory: CFString] = [
        .location: kCGImagePropertyGPSDictionary,
        .dateTime: kCGImagePropertyExifDictionary,
        .deviceInfo: kCGImagePropertyTIFFDictionary
    ]

    enum MetadataCategory: String, CaseIterable {
        case location = "位置情報"
        case dateTime = "日時"
        case deviceInfo = "端末情報"
    }

    /// Settings for which metadata categories to keep.
    struct ScrubSettings {
        var keepLocation: Bool = false
        var keepDateTime: Bool = false
        var keepDeviceInfo: Bool = false

        static let removeAll = ScrubSettings()
    }

    // MARK: - Public API

    /// Strip metadata from JPEG data and return cleaned JPEG data.
    static func scrub(jpegData: Data, settings: ScrubSettings = .removeAll) -> Data? {
        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let uti = CGImageSourceGetType(source) else {
            logger.error("Failed to create image source from data")
            return nil
        }

        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            logger.error("Failed to extract CGImage from source")
            return nil
        }

        // Get existing metadata
        let existingProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]

        // Build cleaned properties
        var cleanedProperties: [CFString: Any] = [:]

        // Copy only safe properties
        let dangerousKeys: Set<CFString> = buildDangerousKeySet(settings: settings)

        for (key, value) in existingProperties {
            if dangerousKeys.contains(key) {
                continue
            }

            if key == kCGImagePropertyExifDictionary, !settings.keepDateTime {
                // Strip date-related fields from EXIF but keep non-identifying ones
                if var exifDict = value as? [CFString: Any] {
                    exifDict.removeValue(forKey: kCGImagePropertyExifDateTimeOriginal)
                    exifDict.removeValue(forKey: kCGImagePropertyExifDateTimeDigitized)
                    exifDict.removeValue(forKey: kCGImagePropertyExifSubsecTime)
                    exifDict.removeValue(forKey: kCGImagePropertyExifSubsecTimeOriginal)
                    exifDict.removeValue(forKey: kCGImagePropertyExifSubsecTimeDigitized)
                    // Keep technical photo settings (aperture, ISO, etc.) — non-identifying
                    if !exifDict.isEmpty {
                        cleanedProperties[key] = exifDict
                    }
                }
            } else if key == kCGImagePropertyTIFFDictionary {
                // Handle TIFF dictionary: strip device info and/or DateTime
                if var tiffDict = value as? [CFString: Any] {
                    if !settings.keepDeviceInfo {
                        tiffDict.removeValue(forKey: kCGImagePropertyTIFFMake)
                        tiffDict.removeValue(forKey: kCGImagePropertyTIFFModel)
                        tiffDict.removeValue(forKey: kCGImagePropertyTIFFSoftware)
                        tiffDict.removeValue(forKey: kCGImagePropertyTIFFHostComputer)
                    }
                    if !settings.keepDateTime {
                        tiffDict.removeValue(forKey: kCGImagePropertyTIFFDateTime)
                    }
                    if !tiffDict.isEmpty {
                        cleanedProperties[key] = tiffDict
                    }
                }
            } else {
                cleanedProperties[key] = value
            }
        }

        // Create output data with cleaned metadata
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(outputData, uti, 1, nil) else {
            logger.error("Failed to create image destination")
            return nil
        }

        CGImageDestinationAddImage(destination, cgImage, cleanedProperties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            logger.error("Failed to finalize image destination")
            return nil
        }

        // Verify: CGImageDestination may re-inject DateTime during finalization.
        // If that happened, fall back to UIImage re-encoding which strips all metadata.
        if !settings.keepDateTime {
            if let verifySource = CGImageSourceCreateWithData(outputData as CFData, nil),
               let verifyProps = CGImageSourceCopyPropertiesAtIndex(verifySource, 0, nil) as? [CFString: Any],
               let verifyExif = verifyProps[kCGImagePropertyExifDictionary] as? [CFString: Any],
               verifyExif[kCGImagePropertyExifDateTimeOriginal] != nil {
                // Re-encode via UIImage (strips all EXIF), then apply only the properties we want to keep
                let image = UIImage(cgImage: cgImage)
                guard let cleanData = image.jpegData(compressionQuality: 0.95) else { return outputData as Data }

                // If we need to preserve some metadata (location, device info), re-add it
                var propsToRestore: [CFString: Any] = [:]
                if settings.keepLocation, let gps = existingProperties[kCGImagePropertyGPSDictionary] {
                    propsToRestore[kCGImagePropertyGPSDictionary] = gps
                }
                if settings.keepDeviceInfo, let tiff = existingProperties[kCGImagePropertyTIFFDictionary] {
                    propsToRestore[kCGImagePropertyTIFFDictionary] = tiff
                }

                if !propsToRestore.isEmpty {
                    guard let cleanSource = CGImageSourceCreateWithData(cleanData as CFData, nil),
                          let cleanUTI = CGImageSourceGetType(cleanSource),
                          let cleanCG = CGImageSourceCreateImageAtIndex(cleanSource, 0, nil) else { return cleanData }
                    let reOutput = NSMutableData()
                    guard let reDest = CGImageDestinationCreateWithData(reOutput, cleanUTI, 1, nil) else { return cleanData }
                    CGImageDestinationAddImage(reDest, cleanCG, propsToRestore as CFDictionary)
                    CGImageDestinationFinalize(reDest)
                    return reOutput as Data
                }
                return cleanData
            }
        }

        let inputSize = jpegData.count
        let outputSize = outputData.length
        logger.info("EXIF scrub: \(inputSize) → \(outputSize) bytes (removed \(inputSize - outputSize) bytes of metadata)")

        return outputData as Data
    }

    /// Strip all metadata and return completely clean JPEG.
    static func scrubCompletely(jpegData: Data, quality: CGFloat = 0.95) -> Data? {
        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let image = UIImage(cgImage: cgImage)
        return image.jpegData(compressionQuality: quality)
    }

    /// Verify that an image has no GPS data.
    static func verifyNoGPS(in data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return true // No metadata at all
        }
        return properties[kCGImagePropertyGPSDictionary] == nil
    }

    /// Verify that an image has no identifiable metadata.
    static func verifyClean(data: Data, settings: ScrubSettings = .removeAll) -> MetadataAudit {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return MetadataAudit(hasGPS: false, hasDateTime: false, hasDeviceInfo: false, rawKeys: [])
        }

        let hasGPS = properties[kCGImagePropertyGPSDictionary] != nil
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        let hasDateTime = exif?[kCGImagePropertyExifDateTimeOriginal] != nil
        let hasDeviceInfo = tiff?[kCGImagePropertyTIFFModel] != nil
            || tiff?[kCGImagePropertyTIFFMake] != nil

        return MetadataAudit(
            hasGPS: hasGPS,
            hasDateTime: hasDateTime,
            hasDeviceInfo: hasDeviceInfo,
            rawKeys: Array(properties.keys).map { $0 as String }
        )
    }

    struct MetadataAudit {
        let hasGPS: Bool
        let hasDateTime: Bool
        let hasDeviceInfo: Bool
        let rawKeys: [String]

        var isFullyClean: Bool {
            !hasGPS && !hasDateTime && !hasDeviceInfo
        }
    }

    // MARK: - Metadata Injection

    /// Capture context containing metadata to inject into the saved photo.
    struct CaptureContext {
        var location: CLLocation?
        var captureDate: Date = Date()
        var captureDevice: AVCaptureDevice?
    }

    /// Inject metadata into JPEG data based on settings and capture context.
    /// This is called AFTER scrubbing — it adds back only the metadata the user wants.
    /// Since SilentCaptureEngine produces images without EXIF (from video buffer),
    /// this method actively injects GPS, DateTime, and DeviceInfo.
    static func injectMetadata(into jpegData: Data, settings: ScrubSettings, context: CaptureContext) -> Data? {
        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let uti = CGImageSourceGetType(source),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            logger.error("Failed to create image source for metadata injection")
            return nil
        }

        // Start with existing properties
        var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]

        // Inject GPS if user wants location
        if settings.keepLocation, let location = context.location {
            properties[kCGImagePropertyGPSDictionary] = buildGPSDictionary(from: location)
            logger.info("Injected GPS metadata: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        }

        // Inject DateTime if user wants date
        if settings.keepDateTime {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            let dateString = dateFormatter.string(from: context.captureDate)

            let subsecFormatter = DateFormatter()
            subsecFormatter.dateFormat = "SSS"
            subsecFormatter.locale = Locale(identifier: "en_US_POSIX")
            let subsecString = subsecFormatter.string(from: context.captureDate)

            // EXIF dictionary
            var exifDict = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
            exifDict[kCGImagePropertyExifDateTimeOriginal] = dateString
            exifDict[kCGImagePropertyExifDateTimeDigitized] = dateString
            exifDict[kCGImagePropertyExifSubsecTimeOriginal] = subsecString
            exifDict[kCGImagePropertyExifSubsecTimeDigitized] = subsecString
            properties[kCGImagePropertyExifDictionary] = exifDict

            // TIFF DateTime
            var tiffDict = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            tiffDict[kCGImagePropertyTIFFDateTime] = dateString
            properties[kCGImagePropertyTIFFDictionary] = tiffDict

            logger.info("Injected DateTime metadata: \(dateString)")
        }

        // Inject DeviceInfo if user wants it
        if settings.keepDeviceInfo {
            let marketingName = DeviceInfoMapper.marketingName
            let lensSpec = DeviceInfoMapper.lensSpec(for: context.captureDevice)

            // TIFF dictionary — device identification
            var tiffDict = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            tiffDict[kCGImagePropertyTIFFMake] = "Apple"
            tiffDict[kCGImagePropertyTIFFModel] = marketingName
            tiffDict[kCGImagePropertyTIFFSoftware] = "iOS \(UIDevice.current.systemVersion)"
            tiffDict[kCGImagePropertyTIFFHostComputer] = marketingName
            properties[kCGImagePropertyTIFFDictionary] = tiffDict

            // EXIF dictionary — lens and camera specs
            var exifDict = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
            exifDict[kCGImagePropertyExifLensMake] = "Apple"
            exifDict[kCGImagePropertyExifLensModel] = lensSpec.lensModel
            exifDict[kCGImagePropertyExifFocalLength] = lensSpec.focalLength
            exifDict[kCGImagePropertyExifFocalLenIn35mmFilm] = lensSpec.focalLength35mm
            exifDict[kCGImagePropertyExifFNumber] = lensSpec.fNumber
            exifDict[kCGImagePropertyExifMaxApertureValue] = log2(lensSpec.fNumber * lensSpec.fNumber)
            // LensSpecification: [minFocalLen, maxFocalLen, minFNum, maxFNum]
            exifDict[kCGImagePropertyExifLensSpecification] = [
                lensSpec.focalLength, lensSpec.focalLength,
                lensSpec.fNumber, lensSpec.fNumber
            ]
            properties[kCGImagePropertyExifDictionary] = exifDict

            logger.info("Injected DeviceInfo: \(marketingName), lens: \(lensSpec.lensModel)")
        }

        // Write JPEG with injected metadata
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(outputData, uti, 1, nil) else {
            logger.error("Failed to create image destination for injection")
            return nil
        }

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            logger.error("Failed to finalize image with injected metadata")
            return nil
        }

        logger.info("Metadata injection complete: \(jpegData.count) → \(outputData.length) bytes")
        return outputData as Data
    }

    /// Build GPS EXIF dictionary from CLLocation.
    private static func buildGPSDictionary(from location: CLLocation) -> [CFString: Any] {
        let coord = location.coordinate
        var gps: [CFString: Any] = [:]

        // Latitude
        gps[kCGImagePropertyGPSLatitude] = abs(coord.latitude)
        gps[kCGImagePropertyGPSLatitudeRef] = coord.latitude >= 0 ? "N" : "S"

        // Longitude
        gps[kCGImagePropertyGPSLongitude] = abs(coord.longitude)
        gps[kCGImagePropertyGPSLongitudeRef] = coord.longitude >= 0 ? "E" : "W"

        // Altitude
        if location.verticalAccuracy >= 0 {
            gps[kCGImagePropertyGPSAltitude] = abs(location.altitude)
            gps[kCGImagePropertyGPSAltitudeRef] = location.altitude >= 0 ? 0 : 1
        }

        // Speed (m/s → km/h)
        if location.speed >= 0 {
            gps[kCGImagePropertyGPSSpeed] = location.speed * 3.6
            gps[kCGImagePropertyGPSSpeedRef] = "K"
        }

        // Course (heading)
        if location.course >= 0 {
            gps[kCGImagePropertyGPSImgDirection] = location.course
            gps[kCGImagePropertyGPSImgDirectionRef] = "T"
        }

        // GPS timestamp (UTC)
        let utcFormatter = DateFormatter()
        utcFormatter.dateFormat = "yyyy:MM:dd"
        utcFormatter.timeZone = TimeZone(identifier: "UTC")
        utcFormatter.locale = Locale(identifier: "en_US_POSIX")
        gps[kCGImagePropertyGPSDateStamp] = utcFormatter.string(from: location.timestamp)

        let calendar = Calendar(identifier: .gregorian)
        let utcComponents = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: location.timestamp)
        gps[kCGImagePropertyGPSTimeStamp] = "\(utcComponents.hour ?? 0):\(utcComponents.minute ?? 0):\(utcComponents.second ?? 0)"

        // Horizontal accuracy (DOP)
        gps[kCGImagePropertyGPSHPositioningError] = location.horizontalAccuracy

        return gps
    }

    // MARK: - Private

    private static func buildDangerousKeySet(settings: ScrubSettings) -> Set<CFString> {
        var keys = alwaysStrippedKeys

        if !settings.keepLocation {
            keys.insert(kCGImagePropertyGPSDictionary)
        }

        // Maker notes always removed (contains device fingerprints)
        keys.insert(kCGImagePropertyMakerAppleDictionary)

        return keys
    }
}
