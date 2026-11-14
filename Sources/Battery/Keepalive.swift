import CoreLocation

/// Keeps the app running in the background while the phone charges, by holding the coarsest location updates iOS
/// offers (Wi-Fi and cell, never GPS). The fixes are thrown away. Started and stopped by `Monitor` at plug and unplug.
@Observable
final class Keepalive: NSObject, CLLocationManagerDelegate {
    private(set) var isRunning = false
    private(set) var authorization: CLAuthorizationStatus
    private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = CLLocationDistanceMax
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = false
    }

    var allowed: Bool { authorization == .authorizedAlways || authorization == .authorizedWhenInUse }

    private var wanted = false

    func start() {
        wanted = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // Always lets a charge that starts while locked be recorded too.
            manager.requestAlwaysAuthorization()
            run()
        case .authorizedAlways:
            run()
        default:
            break
        }
    }

    private func run() {
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        isRunning = true
    }

    func stop() {
        wanted = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isRunning = false
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.wanted, !self.isRunning, self.allowed { self.start() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
