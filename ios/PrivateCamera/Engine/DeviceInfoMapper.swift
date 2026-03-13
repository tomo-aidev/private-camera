import AVFoundation
import UIKit

/// Maps machine identifiers to marketing names and provides accurate lens specifications.
struct DeviceInfoMapper {

    // MARK: - Machine ID → Marketing Name

    /// Get the machine identifier (e.g., "iPhone17,2").
    static var machineIdentifier: String {
        var size: size_t = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }

    /// Convert machine identifier to marketing name (e.g., "iPhone 16 Pro Max").
    static var marketingName: String {
        return modelNameMap[machineIdentifier] ?? UIDevice.current.model
    }

    /// Full EXIF model string (e.g., "Apple iPhone 16 Pro Max").
    static var exifModelName: String {
        return marketingName
    }

    // MARK: - Lens Info from AVCaptureDevice

    /// Lens specification for EXIF metadata.
    struct LensSpec {
        let focalLength: Double        // Actual focal length (mm)
        let focalLength35mm: Int       // 35mm equivalent focal length
        let fNumber: Double            // f-number (aperture)
        let lensModel: String          // Human-readable lens description
    }

    /// Get lens specification for the currently active camera device.
    static func lensSpec(for device: AVCaptureDevice?) -> LensSpec {
        guard let device = device else {
            return defaultLensSpec
        }

        // Determine lens type from device type and position
        let lensType: String
        if device.position == .front {
            lensType = "front"
        } else {
            switch device.deviceType {
            case .builtInUltraWideCamera:
                lensType = "ultrawide"
            case .builtInTelephotoCamera:
                lensType = "telephoto"
            default:
                lensType = "wide"
            }
        }

        // For logical multi-camera, determine active constituent from zoom factor
        let effectiveLensType: String
        if device.deviceType == .builtInTripleCamera ||
           device.deviceType == .builtInDualWideCamera ||
           device.deviceType == .builtInDualCamera {
            effectiveLensType = activeLensType(for: device)
        } else {
            effectiveLensType = lensType
        }

        // Look up specs for this device + lens combination
        let machineId = machineIdentifier
        if let specs = deviceLensSpecs[machineId], let spec = specs[effectiveLensType] {
            return spec
        }

        // Fallback: use known specs by lens type
        return fallbackLensSpec(for: effectiveLensType)
    }

    /// Determine which physical lens is active on a logical multi-camera based on zoom factor.
    private static func activeLensType(for device: AVCaptureDevice) -> String {
        let zoom = device.videoZoomFactor
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }

        if switchOvers.count >= 2 {
            if zoom < switchOvers[0] {
                return "ultrawide"
            } else if zoom < switchOvers[1] {
                return "wide"
            } else {
                return "telephoto"
            }
        } else if switchOvers.count == 1 {
            if zoom < switchOvers[0] {
                return "ultrawide"
            } else {
                return "wide"
            }
        }
        return "wide"
    }

    private static func fallbackLensSpec(for lensType: String) -> LensSpec {
        switch lensType {
        case "ultrawide":
            return LensSpec(focalLength: 2.22, focalLength35mm: 13, fNumber: 2.2,
                          lensModel: "iPhone back ultra wide camera 2.22mm f/2.2")
        case "telephoto":
            return LensSpec(focalLength: 6.765, focalLength35mm: 120, fNumber: 2.8,
                          lensModel: "iPhone back telephoto camera 6.765mm f/2.8")
        case "front":
            return LensSpec(focalLength: 2.69, focalLength35mm: 23, fNumber: 1.9,
                          lensModel: "iPhone front camera 2.69mm f/1.9")
        default: // wide
            return LensSpec(focalLength: 6.765, focalLength35mm: 24, fNumber: 1.78,
                          lensModel: "iPhone back camera 6.765mm f/1.78")
        }
    }

    private static let defaultLensSpec = LensSpec(
        focalLength: 6.765, focalLength35mm: 24, fNumber: 1.78,
        lensModel: "iPhone back camera 6.765mm f/1.78"
    )

    // MARK: - Device-Specific Lens Specs

    /// Lens specifications per device model and lens type.
    /// Key: machine identifier, Value: dictionary of lens type → spec
    private static let deviceLensSpecs: [String: [String: LensSpec]] = [
        // iPhone 16 Pro Max
        "iPhone17,2": [
            "ultrawide": LensSpec(focalLength: 2.22, focalLength35mm: 13, fNumber: 2.2,
                                lensModel: "iPhone 16 Pro Max back ultra wide camera 2.22mm f/2.2"),
            "wide": LensSpec(focalLength: 6.765, focalLength35mm: 24, fNumber: 1.78,
                           lensModel: "iPhone 16 Pro Max back camera 6.765mm f/1.78"),
            "telephoto": LensSpec(focalLength: 18.62, focalLength35mm: 120, fNumber: 2.8,
                                lensModel: "iPhone 16 Pro Max back telephoto camera 18.62mm f/2.8"),
            "front": LensSpec(focalLength: 2.69, focalLength35mm: 23, fNumber: 1.9,
                            lensModel: "iPhone 16 Pro Max front TrueDepth camera 2.69mm f/1.9"),
        ],
        // iPhone 16 Pro
        "iPhone17,1": [
            "ultrawide": LensSpec(focalLength: 2.22, focalLength35mm: 13, fNumber: 2.2,
                                lensModel: "iPhone 16 Pro back ultra wide camera 2.22mm f/2.2"),
            "wide": LensSpec(focalLength: 6.765, focalLength35mm: 24, fNumber: 1.78,
                           lensModel: "iPhone 16 Pro back camera 6.765mm f/1.78"),
            "telephoto": LensSpec(focalLength: 18.62, focalLength35mm: 120, fNumber: 2.8,
                                lensModel: "iPhone 16 Pro back telephoto camera 18.62mm f/2.8"),
            "front": LensSpec(focalLength: 2.69, focalLength35mm: 23, fNumber: 1.9,
                            lensModel: "iPhone 16 Pro front TrueDepth camera 2.69mm f/1.9"),
        ],
        // iPhone 16
        "iPhone17,3": [
            "ultrawide": LensSpec(focalLength: 2.22, focalLength35mm: 13, fNumber: 2.2,
                                lensModel: "iPhone 16 back ultra wide camera 2.22mm f/2.2"),
            "wide": LensSpec(focalLength: 6.765, focalLength35mm: 26, fNumber: 1.6,
                           lensModel: "iPhone 16 back camera 6.765mm f/1.6"),
            "front": LensSpec(focalLength: 2.69, focalLength35mm: 23, fNumber: 1.9,
                            lensModel: "iPhone 16 front TrueDepth camera 2.69mm f/1.9"),
        ],
        // iPhone 15 Pro Max
        "iPhone16,2": [
            "ultrawide": LensSpec(focalLength: 2.22, focalLength35mm: 13, fNumber: 2.2,
                                lensModel: "iPhone 15 Pro Max back ultra wide camera 2.22mm f/2.2"),
            "wide": LensSpec(focalLength: 6.765, focalLength35mm: 24, fNumber: 1.78,
                           lensModel: "iPhone 15 Pro Max back camera 6.765mm f/1.78"),
            "telephoto": LensSpec(focalLength: 18.62, focalLength35mm: 120, fNumber: 2.8,
                                lensModel: "iPhone 15 Pro Max back telephoto camera 18.62mm f/2.8"),
            "front": LensSpec(focalLength: 2.69, focalLength35mm: 23, fNumber: 1.9,
                            lensModel: "iPhone 15 Pro Max front TrueDepth camera 2.69mm f/1.9"),
        ],
        // iPhone 15 Pro
        "iPhone16,1": [
            "ultrawide": LensSpec(focalLength: 2.22, focalLength35mm: 13, fNumber: 2.2,
                                lensModel: "iPhone 15 Pro back ultra wide camera 2.22mm f/2.2"),
            "wide": LensSpec(focalLength: 6.765, focalLength35mm: 24, fNumber: 1.78,
                           lensModel: "iPhone 15 Pro back camera 6.765mm f/1.78"),
            "telephoto": LensSpec(focalLength: 7.36, focalLength35mm: 77, fNumber: 2.8,
                                lensModel: "iPhone 15 Pro back telephoto camera 7.36mm f/2.8"),
            "front": LensSpec(focalLength: 2.69, focalLength35mm: 23, fNumber: 1.9,
                            lensModel: "iPhone 15 Pro front TrueDepth camera 2.69mm f/1.9"),
        ],
    ]

    // MARK: - Model Name Map

    private static let modelNameMap: [String: String] = [
        // iPhone 16 series
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        // iPhone 15 series
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        // iPhone 14 series
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        // iPhone 13 series
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        // iPhone 12 series
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        // iPhone SE
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone12,8": "iPhone SE (2nd generation)",
        // iPad (common ones)
        "iPad16,3": "iPad Pro 13-inch (M4)",
        "iPad16,4": "iPad Pro 13-inch (M4)",
        "iPad16,5": "iPad Pro 11-inch (M4)",
        "iPad16,6": "iPad Pro 11-inch (M4)",
        // Simulator
        "arm64": "Simulator",
        "x86_64": "Simulator",
    ]
}
