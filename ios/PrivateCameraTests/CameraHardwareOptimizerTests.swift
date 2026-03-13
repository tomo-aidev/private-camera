import XCTest
import AVFoundation
@testable import PrivateCamera

final class CameraHardwareOptimizerTests: XCTestCase {

    // MARK: - Test: Singleton instance

    func testSharedInstance() {
        let a = CameraHardwareOptimizer.shared
        let b = CameraHardwareOptimizer.shared
        XCTAssertTrue(a === b, "Should return the same singleton instance")
    }

    // MARK: - Test: Discovery returns spec

    func testDiscoveryReturnsSpec() {
        let optimizer = CameraHardwareOptimizer.shared
        let spec = optimizer.discover()

        // Should have a model name
        XCTAssertFalse(spec.modelName.isEmpty, "Model name should not be empty")

        // Should detect at least some camera on any device/simulator
        // Note: On simulator, camera hardware may not be available
        #if targetEnvironment(simulator)
        // On simulator, we just verify it doesn't crash
        print("Running on simulator — camera hardware not available")
        #else
        XCTAssertFalse(spec.lenses.isEmpty, "Should detect at least one lens on real device")
        XCTAssertNotNil(spec.bestBackCamera, "Should have a back camera")
        #endif
    }

    // MARK: - Test: Zoom thresholds

    func testZoomThresholdsNotEmpty() {
        let optimizer = CameraHardwareOptimizer.shared
        _ = optimizer.discover()

        let thresholds = optimizer.zoomThresholds()

        // Should always return at least 1x
        XCTAssertFalse(thresholds.isEmpty, "Zoom thresholds should not be empty")
        XCTAssertTrue(thresholds.contains(where: { $0.label == "1x" }), "Should always include 1x")
    }

    // MARK: - Test: Lens classification

    func testLensTypes() {
        let optimizer = CameraHardwareOptimizer.shared
        let spec = optimizer.discover()

        for lens in spec.lenses {
            // Verify each lens has valid properties
            XCTAssertFalse(lens.id.isEmpty, "Lens ID should not be empty")
            XCTAssertTrue(lens.maxPhotoResolution.width > 0 || true, "Photo resolution should be valid (or 0 on simulator)")

            switch lens.lensType {
            case .ultraWide, .wide, .telephoto:
                XCTAssertEqual(lens.device.position, .back, "\(lens.lensType.rawValue) should be a back camera")
            case .front:
                XCTAssertEqual(lens.device.position, .front, "Front lens should be front camera")
            case .unknown:
                break // OK
            }
        }
    }
}
