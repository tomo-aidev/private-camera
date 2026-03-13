import AVFoundation
import UIKit
import CoreImage
import os.log

/// Captures full-resolution still images from the video data output buffer,
/// bypassing the standard `takePicture` API to avoid system shutter sound.
///
/// This approach extracts frames from the live video stream, so the captured image
/// benefits from the device ISP pipeline (noise reduction, tone mapping, etc.)
/// while producing zero audible feedback.
final class SilentCaptureEngine: NSObject {

    private let logger = Logger(subsystem: "com.privatecamera", category: "SilentCapture")
    private let videoDataOutput: AVCaptureVideoDataOutput
    private let processingQueue = DispatchQueue(label: "com.privatecamera.silentcapture", qos: .userInitiated)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// The latest sample buffer from the video stream.
    private var latestBuffer: CMSampleBuffer?
    private let bufferLock = NSLock()

    /// Continuation for async capture.
    private var captureContinuation: CheckedContinuation<UIImage?, Never>?

    /// Whether a capture is currently in progress.
    private(set) var isCapturing = false

    init(videoDataOutput: AVCaptureVideoDataOutput) {
        self.videoDataOutput = videoDataOutput
        super.init()
        videoDataOutput.setSampleBufferDelegate(self, queue: processingQueue)
    }

    // MARK: - Public API

    /// Capture a still image silently from the current video buffer.
    /// Uses the highest quality frame available at the moment of capture.
    func captureStillImage() async -> UIImage? {
        return await withCheckedContinuation { continuation in
            bufferLock.lock()
            self.isCapturing = true

            if let buffer = self.latestBuffer {
                // We have a buffer ready — process immediately
                let image = self.processBuffer(buffer)
                self.isCapturing = false
                bufferLock.unlock()
                continuation.resume(returning: image)
            } else {
                // Wait for next buffer
                self.captureContinuation = continuation
                bufferLock.unlock()
            }
        }
    }

    // MARK: - Buffer Processing

    private func processBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            logger.error("Failed to get pixel buffer from sample buffer")
            return nil
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Apply ISP-equivalent enhancements
        let enhanced = applyEnhancements(to: ciImage)

        // Render to CGImage at full resolution
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard let cgImage = ciContext.createCGImage(enhanced, from: CGRect(x: 0, y: 0, width: width, height: height)) else {
            logger.error("Failed to create CGImage from CIImage")
            return nil
        }

        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)

        logger.info("Silent capture: \(width)x\(height) pixels")
        return image
    }

    /// Apply post-processing enhancements that mimic ISP behavior.
    /// These run on the GPU via Core Image for maximum performance.
    private func applyEnhancements(to image: CIImage) -> CIImage {
        var result = image

        // 1. Auto-adjustment (exposure, color balance, etc.)
        let adjustments = result.autoAdjustmentFilters()
        for filter in adjustments {
            filter.setValue(result, forKey: kCIInputImageKey)
            if let output = filter.outputImage {
                result = output
            }
        }

        // 2. Noise reduction (CINoiseReduction or temporal NR)
        if let noiseReduction = CIFilter(name: "CINoiseReduction") {
            noiseReduction.setValue(result, forKey: kCIInputImageKey)
            noiseReduction.setValue(0.02, forKey: "inputNoiseLevel")
            noiseReduction.setValue(0.40, forKey: "inputSharpness")
            if let output = noiseReduction.outputImage {
                result = output
            }
        }

        // 3. Subtle sharpening
        if let sharpen = CIFilter(name: "CISharpenLuminance") {
            sharpen.setValue(result, forKey: kCIInputImageKey)
            sharpen.setValue(0.4, forKey: kCIInputSharpnessKey)
            if let output = sharpen.outputImage {
                result = output
            }
        }

        return result
    }

    // MARK: - JPEG Data

    /// Convert a UIImage to maximum quality JPEG data.
    static func toJPEGData(_ image: UIImage, quality: CGFloat = 1.0) -> Data? {
        return image.jpegData(compressionQuality: quality)
    }

    /// Convert a UIImage to HEIF data for better compression with quality preservation.
    static func toHEIFData(_ image: UIImage) -> Data? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let context = CIContext()
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        return try? context.heifRepresentation(
            of: ciImage,
            format: .RGBA8,
            colorSpace: colorSpace,
            options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.95]
        )
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension SilentCaptureEngine: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        bufferLock.lock()

        self.latestBuffer = sampleBuffer

        // If there's a pending capture request, fulfill it
        if let continuation = captureContinuation {
            let image = processBuffer(sampleBuffer)
            self.captureContinuation = nil
            self.isCapturing = false
            bufferLock.unlock()
            continuation.resume(returning: image)
        } else {
            bufferLock.unlock()
        }
    }
}
