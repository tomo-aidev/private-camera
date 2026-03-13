import AVFoundation
import os.log

// MARK: - Device Camera Specification

struct CameraLensInfo: Identifiable {
    let id: String
    let device: AVCaptureDevice
    let lensType: LensType
    let maxPhotoResolution: CMVideoDimensions
    let maxVideoResolution: CMVideoDimensions
    let bestPhotoFormat: AVCaptureDevice.Format?
    let bestVideoFormat: AVCaptureDevice.Format?
    let hasDepthData: Bool
    let supportsHDR: Bool
    let minISO: Float
    let maxISO: Float
    let minExposureDuration: CMTime
    let maxExposureDuration: CMTime
    let videoZoomFactorRange: ClosedRange<CGFloat>

    enum LensType: String, CaseIterable {
        case ultraWide = "Ultra Wide"
        case wide = "Wide"
        case telephoto = "Telephoto"
        case front = "Front"
        case unknown = "Unknown"
    }
}

struct DeviceCameraSpec {
    let modelName: String
    let lenses: [CameraLensInfo]
    let hasLiDAR: Bool
    let hasMultiCamSupport: Bool
    let logicalMultiCamera: AVCaptureDevice?
    let bestBackCamera: AVCaptureDevice?
    let bestFrontCamera: AVCaptureDevice?
}

// MARK: - CameraHardwareOptimizer

final class CameraHardwareOptimizer {

    static let shared = CameraHardwareOptimizer()
    private let logger = Logger(subsystem: "com.privatecamera", category: "HardwareOptimizer")

    private(set) var deviceSpec: DeviceCameraSpec?

    private init() {}

    // MARK: - Discovery

    /// Run full hardware discovery and log results.
    @discardableResult
    func discover() -> DeviceCameraSpec {
        logger.info("=== Camera Hardware Discovery Start ===")

        let discoveryBack = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera,
                .builtInUltraWideCamera,
                .builtInTelephotoCamera
            ],
            mediaType: .video,
            position: .back
        )

        let discoveryFront = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .front
        )

        // Check LiDAR
        let hasLiDAR = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInLiDARDepthCamera],
            mediaType: .video,
            position: .back
        ).devices.isEmpty == false

        // Multi-cam support
        let hasMultiCam = AVCaptureMultiCamSession.isMultiCamSupported

        // Find logical multi-camera (triple > dual wide > dual)
        let logicalMulti = discoveryBack.devices.first(where: { $0.deviceType == .builtInTripleCamera })
            ?? discoveryBack.devices.first(where: { $0.deviceType == .builtInDualWideCamera })
            ?? discoveryBack.devices.first(where: { $0.deviceType == .builtInDualCamera })

        // Enumerate individual physical lenses
        var lenses: [CameraLensInfo] = []

        // Back cameras - prefer using constituents from the logical multi-cam
        let backDevices: [AVCaptureDevice]
        if let logicalMulti {
            // Get the physical constituent devices
            let constituentTypes: [AVCaptureDevice.DeviceType] = [
                .builtInUltraWideCamera,
                .builtInWideAngleCamera,
                .builtInTelephotoCamera
            ]
            backDevices = constituentTypes.compactMap { type in
                AVCaptureDevice.DiscoverySession(
                    deviceTypes: [type],
                    mediaType: .video,
                    position: .back
                ).devices.first
            }
        } else {
            backDevices = discoveryBack.devices.filter {
                $0.deviceType == .builtInWideAngleCamera
                || $0.deviceType == .builtInUltraWideCamera
                || $0.deviceType == .builtInTelephotoCamera
            }
        }

        for device in backDevices {
            let info = analyzeLens(device)
            lenses.append(info)
        }

        // Front camera
        if let frontDevice = discoveryFront.devices.first {
            let info = analyzeLens(frontDevice)
            lenses.append(info)
        }

        let modelName = getDeviceModelName()

        let spec = DeviceCameraSpec(
            modelName: modelName,
            lenses: lenses,
            hasLiDAR: hasLiDAR,
            hasMultiCamSupport: hasMultiCam,
            logicalMultiCamera: logicalMulti,
            bestBackCamera: logicalMulti ?? discoveryBack.devices.first(where: { $0.deviceType == .builtInWideAngleCamera }),
            bestFrontCamera: discoveryFront.devices.first
        )

        self.deviceSpec = spec
        logSpec(spec)

        logger.info("=== Camera Hardware Discovery Complete ===")
        return spec
    }

    // MARK: - Lens Analysis

    private func analyzeLens(_ device: AVCaptureDevice) -> CameraLensInfo {
        let lensType = classifyLens(device)

        // Find best photo format (max pixel count)
        let photoFormats = device.formats.filter { format in
            let mediaType = CMFormatDescriptionGetMediaType(format.formatDescription)
            return mediaType == kCMMediaType_Video
        }

        let bestPhotoFormat = photoFormats.max { a, b in
            let dimA = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
            let dimB = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
            return Int(dimA.width) * Int(dimA.height) < Int(dimB.width) * Int(dimB.height)
        }

        let maxPhotoDim: CMVideoDimensions
        if let bestPhotoFormat {
            maxPhotoDim = CMVideoFormatDescriptionGetDimensions(bestPhotoFormat.formatDescription)
        } else {
            maxPhotoDim = CMVideoDimensions(width: 0, height: 0)
        }

        // Find best video format (max resolution at >= 30fps)
        let bestVideoFormat = photoFormats
            .filter { format in
                format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
            }
            .max { a, b in
                let dimA = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
                let dimB = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
                return Int(dimA.width) * Int(dimA.height) < Int(dimB.width) * Int(dimB.height)
            }

        let maxVideoDim: CMVideoDimensions
        if let bestVideoFormat {
            maxVideoDim = CMVideoFormatDescriptionGetDimensions(bestVideoFormat.formatDescription)
        } else {
            maxVideoDim = maxPhotoDim
        }

        // HDR support
        let supportsHDR = photoFormats.contains { format in
            format.isVideoHDRSupported
        }

        // Depth
        let hasDepth = !device.activeFormat.supportedDepthDataFormats.isEmpty
            || photoFormats.contains { !$0.supportedDepthDataFormats.isEmpty }

        return CameraLensInfo(
            id: device.uniqueID,
            device: device,
            lensType: lensType,
            maxPhotoResolution: maxPhotoDim,
            maxVideoResolution: maxVideoDim,
            bestPhotoFormat: bestPhotoFormat,
            bestVideoFormat: bestVideoFormat,
            hasDepthData: hasDepth,
            supportsHDR: supportsHDR,
            minISO: device.activeFormat.minISO,
            maxISO: device.activeFormat.maxISO,
            minExposureDuration: device.activeFormat.minExposureDuration,
            maxExposureDuration: device.activeFormat.maxExposureDuration,
            videoZoomFactorRange: 1.0...device.maxAvailableVideoZoomFactor
        )
    }

    private func classifyLens(_ device: AVCaptureDevice) -> CameraLensInfo.LensType {
        if device.position == .front { return .front }
        switch device.deviceType {
        case .builtInUltraWideCamera: return .ultraWide
        case .builtInTelephotoCamera: return .telephoto
        case .builtInWideAngleCamera: return .wide
        default: return .unknown
        }
    }

    // MARK: - Format Selection

    /// Select the optimal format for the given device targeting maximum still-image resolution.
    func applyOptimalPhotoFormat(to device: AVCaptureDevice) throws {
        guard let spec = deviceSpec,
              let lensInfo = spec.lenses.first(where: { $0.device.uniqueID == device.uniqueID }),
              let bestFormat = lensInfo.bestPhotoFormat else {
            logger.warning("No optimal format found for device \(device.localizedName)")
            return
        }

        try device.lockForConfiguration()
        device.activeFormat = bestFormat

        // Enable HDR if available
        if bestFormat.isVideoHDRSupported {
            device.automaticallyAdjustsVideoHDREnabled = false
            device.isVideoHDREnabled = true
        }

        // Set optimal frame rate (30fps for photo mode balance)
        let targetFPS: Double = 30
        for range in bestFormat.videoSupportedFrameRateRanges {
            if range.maxFrameRate >= targetFPS {
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
                break
            }
        }

        device.unlockForConfiguration()

        let dim = CMVideoFormatDescriptionGetDimensions(bestFormat.formatDescription)
        logger.info("Applied optimal photo format: \(dim.width)x\(dim.height) to \(device.localizedName)")
    }

    /// Select the optimal format for video capture targeting max resolution at 60fps if possible.
    func applyOptimalVideoFormat(to device: AVCaptureDevice) throws {
        guard let spec = deviceSpec,
              let lensInfo = spec.lenses.first(where: { $0.device.uniqueID == device.uniqueID }) else {
            return
        }

        // Prefer 4K@60 > 4K@30 > max resolution
        let targetFormats = device.formats
            .filter { format in
                let dim = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let mediaType = CMFormatDescriptionGetMediaType(format.formatDescription)
                return mediaType == kCMMediaType_Video && dim.width >= 1920
            }
            .sorted { a, b in
                let dimA = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
                let dimB = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
                let fpsA = a.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
                let fpsB = b.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
                // Prioritize resolution first, then fps
                let scoreA = Int(dimA.width) * Int(dimA.height) * Int(fpsA)
                let scoreB = Int(dimB.width) * Int(dimB.height) * Int(fpsB)
                return scoreA > scoreB
            }

        guard let bestFormat = targetFormats.first ?? lensInfo.bestVideoFormat else { return }

        try device.lockForConfiguration()
        device.activeFormat = bestFormat

        if bestFormat.isVideoHDRSupported {
            device.automaticallyAdjustsVideoHDREnabled = false
            device.isVideoHDREnabled = true
        }

        let maxFPS = bestFormat.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30
        let targetFPS = min(maxFPS, 60)
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))

        device.unlockForConfiguration()

        let dim = CMVideoFormatDescriptionGetDimensions(bestFormat.formatDescription)
        logger.info("Applied optimal video format: \(dim.width)x\(dim.height)@\(targetFPS)fps to \(device.localizedName)")
    }

    // MARK: - Format Selection for Full Zoom Range

    /// Find the best format for a camera device.
    /// On builtInTripleCamera, zoom factor 1.0 IS the ultra-wide lens — no special format
    /// probing is needed. All formats support the full zoom range (1.0 to max).
    /// Selects by: HDR support (preferred) then resolution (highest).
    func findBestFormatWithFullZoomRange(device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let candidates = device.formats.filter { format in
            let mt = CMFormatDescriptionGetMediaType(format.formatDescription)
            guard mt == kCMMediaType_Video else { return false }
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width >= 1920 else { return false }
            return format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
        }

        guard !candidates.isEmpty else { return nil }

        // Prefer HDR-capable formats, then highest resolution
        let best = candidates.max { a, b in
            let dA = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
            let dB = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
            let pixA = Int(dA.width) * Int(dA.height)
            let pixB = Int(dB.width) * Int(dB.height)
            let hdrA = a.isVideoHDRSupported ? 1 : 0
            let hdrB = b.isVideoHDRSupported ? 1 : 0
            return (hdrA, pixA) < (hdrB, pixB)
        }

        if let best {
            let dims = CMVideoFormatDescriptionGetDimensions(best.formatDescription)
            logger.info("Selected format: \(dims.width)x\(dims.height) HDR:\(best.isVideoHDRSupported)")
        }

        return best
    }

    // MARK: - Zoom Mapping

    /// The divisor to convert raw AVFoundation zoom factors to user-facing display values.
    /// On builtInTripleCamera, raw zoom 1.0 = ultra-wide, and the first switchover
    /// (typically raw 2.0) = the wide lens = display "1x".
    /// Display zoom = raw zoom / divisor.
    var zoomDisplayDivisor: CGFloat {
        guard let spec = deviceSpec, let multiCam = spec.logicalMultiCamera else { return 1.0 }
        let hasUltraWide = spec.lenses.contains { $0.lensType == .ultraWide }
        guard hasUltraWide else { return 1.0 }
        let switchOvers = multiCam.virtualDeviceSwitchOverVideoZoomFactors
        if let first = switchOvers.first {
            return CGFloat(truncating: first)
        }
        return 1.0
    }

    /// Return the zoom factor thresholds for switching between lenses on the logical multi-camera.
    /// Uses virtualDeviceSwitchOverVideoZoomFactors to determine correct lens boundaries.
    /// On builtInTripleCamera: raw zoom 1.0 = ultra-wide ("0.5x"), first switchover = wide ("1x").
    func zoomThresholds() -> [(label: String, factor: CGFloat)] {
        guard let spec = deviceSpec, let multiCam = spec.logicalMultiCamera else {
            return [(label: "1x", factor: 1.0)]
        }

        let switchOvers = multiCam.virtualDeviceSwitchOverVideoZoomFactors
        let hasUltraWide = spec.lenses.contains { $0.lensType == .ultraWide }
        var thresholds: [(label: String, factor: CGFloat)] = []

        if hasUltraWide && !switchOvers.isEmpty {
            let divisor = CGFloat(truncating: switchOvers[0])

            // Ultra-wide at raw 1.0 (display "0.5x")
            thresholds.append((label: "0.5x", factor: 1.0))

            // Wide lens at first switchover (display "1x")
            thresholds.append((label: "1x", factor: divisor))

            // 2x (center crop of 48MP sensor or digital zoom)
            let twoXRaw = divisor * 2.0
            if twoXRaw <= multiCam.maxAvailableVideoZoomFactor {
                thresholds.append((label: "2x", factor: twoXRaw))
            }

            // Telephoto at second switchover
            if switchOvers.count > 1 {
                let teleFactor = CGFloat(truncating: switchOvers[1])
                let displayValue = teleFactor / divisor
                let label = displayValue == floor(displayValue)
                    ? String(format: "%.0fx", displayValue)
                    : String(format: "%.1fx", displayValue)
                thresholds.append((label: label, factor: teleFactor))
            }

            logger.info("Zoom thresholds (ultra-wide device, divisor=\(divisor)): \(thresholds.map { "\($0.label)=\($0.factor)" })")
        } else {
            thresholds.append((label: "1x", factor: 1.0))
            if multiCam.maxAvailableVideoZoomFactor >= 2.0 {
                thresholds.append((label: "2x", factor: 2.0))
            }
        }

        return thresholds
    }

    // MARK: - Utility

    private func getDeviceModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return partial }
            return partial + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    private func logSpec(_ spec: DeviceCameraSpec) {
        logger.info("Device: \(spec.modelName)")
        logger.info("LiDAR: \(spec.hasLiDAR)")
        logger.info("MultiCam: \(spec.hasMultiCamSupport)")
        logger.info("Logical Multi-Camera: \(spec.logicalMultiCamera?.localizedName ?? "None")")
        logger.info("Lenses found: \(spec.lenses.count)")

        for lens in spec.lenses {
            logger.info("""
              [\(lens.lensType.rawValue)] \(lens.device.localizedName)
                Max Photo: \(lens.maxPhotoResolution.width)x\(lens.maxPhotoResolution.height)
                Max Video: \(lens.maxVideoResolution.width)x\(lens.maxVideoResolution.height)
                HDR: \(lens.supportsHDR) | Depth: \(lens.hasDepthData)
                ISO: \(lens.minISO)-\(lens.maxISO)
                Zoom: \(lens.videoZoomFactorRange.lowerBound)x-\(lens.videoZoomFactorRange.upperBound)x
            """)
        }
    }
}
