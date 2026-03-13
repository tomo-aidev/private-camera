import CoreLocation
import os.log

/// Manages location services for embedding GPS coordinates in photo metadata.
/// Requests permission dynamically when user enables location in settings.
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = LocationManager()

    private let manager = CLLocationManager()
    private let logger = Logger(subsystem: "com.privatecamera", category: "LocationManager")

    /// Most recent location (updated continuously while authorized).
    @Published var currentLocation: CLLocation?

    /// Current authorization status.
    @Published var authorizationStatus: CLAuthorizationStatus

    /// Whether location is available and authorized.
    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    private override init() {
        authorizationStatus = CLLocationManager().authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5 // Update every 5 meters
    }

    // MARK: - Public

    /// Request location permission. Called when user enables "include location" in settings.
    func requestPermission() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            startUpdating()
        } else {
            // Denied or restricted - user needs to go to Settings
            logger.warning("Location permission denied or restricted")
        }
    }

    /// Start location updates.
    func startUpdating() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
        logger.info("Started location updates")
    }

    /// Stop location updates.
    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    /// Get the latest GPS coordinates for EXIF embedding.
    /// Returns nil if location is not available or not authorized.
    func getLatestCoordinates() -> CLLocation? {
        guard isAuthorized else { return nil }
        return currentLocation
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            currentLocation = location
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            if self.isAuthorized {
                self.startUpdating()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("Location error: \(error.localizedDescription)")
    }
}
