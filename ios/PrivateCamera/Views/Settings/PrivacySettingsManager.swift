import SwiftUI
import UIKit

// MARK: - Photo Resolution

enum PhotoResolution: String, CaseIterable, Identifiable {
    case mp5 = "5MP"
    case mp8 = "8MP"
    case mp12 = "12MP"
    case mp48 = "48MP"

    var id: String { rawValue }

    /// Target pixel count (width * height)
    var targetPixels: Int {
        switch self {
        case .mp5: return 2592 * 1944      // ~5MP
        case .mp8: return 3264 * 2448      // ~8MP
        case .mp12: return 4032 * 3024     // ~12MP
        case .mp48: return 8064 * 6048     // ~48MP
        }
    }

    var targetWidth: Int32 {
        switch self {
        case .mp5: return 2592
        case .mp8: return 3264
        case .mp12: return 4032
        case .mp48: return 8064
        }
    }

    /// Resize an image to match this resolution setting, preserving aspect ratio.
    /// Returns the original image if it's already smaller than the target.
    func resized(_ image: UIImage) -> UIImage {
        let srcW = image.size.width
        let srcH = image.size.height
        let srcPixels = Int(srcW * srcH)

        // Already at or below target — return as-is
        if srcPixels <= targetPixels { return image }

        // Scale factor to match target pixel count
        let scale = sqrt(Double(targetPixels) / Double(srcPixels))
        let newW = Int(srcW * scale)
        let newH = Int(srcH * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: newW, height: newH), format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: newW, height: newH))
        }
    }
}

// MARK: - Video Resolution

enum VideoResolution: String, CaseIterable, Identifiable {
    case hd = "HD"
    case fourK = "4K"

    var id: String { rawValue }

    var width: Int32 {
        switch self {
        case .hd: return 1920
        case .fourK: return 3840
        }
    }

    var height: Int32 {
        switch self {
        case .hd: return 1080
        case .fourK: return 2160
        }
    }
}

// MARK: - Video Frame Rate

enum VideoFrameRate: Int, CaseIterable, Identifiable {
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60
    case fps120 = 120

    var id: Int { rawValue }

    var label: String { "\(rawValue)fps" }
}

// MARK: - Save Destination

enum SaveDestination: String, CaseIterable {
    case box = "box"
    case cameraRoll = "cameraRoll"

    var label: String {
        switch self {
        case .box: return "BOXに入れる"
        case .cameraRoll: return "カメラロールに直接保存"
        }
    }

    var icon: String {
        switch self {
        case .box: return "lock.shield"
        case .cameraRoll: return "photo.on.rectangle"
        }
    }
}

/// Centralized manager for privacy settings.
/// Uses @AppStorage for persistence and generates ExifScrubber.ScrubSettings.
final class PrivacySettingsManager: ObservableObject {

    static let shared = PrivacySettingsManager()

    // MARK: - Privacy

    /// When true, location data is NOT included in photos (default: true = exclude location)
    @AppStorage("privacy.removeLocation") var removeLocation: Bool = true

    /// When true, date/time data is NOT included in photos (default: false = include date)
    @AppStorage("privacy.removeDateTime") var removeDateTime: Bool = false

    /// When true, device info is NOT included in photos (default: false = include device info)
    @AppStorage("privacy.removeDeviceInfo") var removeDeviceInfo: Bool = false

    // MARK: - Save Destination

    /// Save destination: "box" (default) or "cameraRoll"
    @AppStorage("saveDestination") var saveDestinationRaw: String = SaveDestination.box.rawValue

    var saveDestination: SaveDestination {
        get { SaveDestination(rawValue: saveDestinationRaw) ?? .box }
        set { saveDestinationRaw = newValue.rawValue }
    }

    // MARK: - Launch

    /// When true, auto-start video recording on app launch
    @AppStorage("autoRecordOnLaunch") var autoRecordOnLaunch: Bool = false

    // MARK: - Photo Settings

    @AppStorage("photo.resolution") var photoResolutionRaw: String = PhotoResolution.mp12.rawValue

    var photoResolution: PhotoResolution {
        get { PhotoResolution(rawValue: photoResolutionRaw) ?? .mp12 }
        set { photoResolutionRaw = newValue.rawValue }
    }

    // MARK: - Video Settings

    @AppStorage("video.resolution") var videoResolutionRaw: String = VideoResolution.fourK.rawValue
    @AppStorage("video.frameRate") var videoFrameRateRaw: Int = VideoFrameRate.fps30.rawValue

    var videoResolution: VideoResolution {
        get { VideoResolution(rawValue: videoResolutionRaw) ?? .fourK }
        set { videoResolutionRaw = newValue.rawValue }
    }

    var videoFrameRate: VideoFrameRate {
        get { VideoFrameRate(rawValue: videoFrameRateRaw) ?? .fps30 }
        set { videoFrameRateRaw = newValue.rawValue }
    }

    /// Generate ExifScrubber.ScrubSettings from current settings.
    /// Note: ScrubSettings uses "keep" semantics, while UI uses "remove" semantics.
    var currentScrubSettings: ExifScrubber.ScrubSettings {
        ExifScrubber.ScrubSettings(
            keepLocation: !removeLocation,
            keepDateTime: !removeDateTime,
            keepDeviceInfo: !removeDeviceInfo
        )
    }

    private init() {}
}
