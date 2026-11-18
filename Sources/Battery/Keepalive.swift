import CoreLocation
import UIKit

/// Keeps the app running in the background while the phone charges, by holding the coarsest location updates iOS
/// offers (Wi-Fi and cell, never GPS). The fixes are thrown away. Started and stopped by `Monitor` at plug and unplug.
/// While Using only lets updates start on screen; Always lets a charge that starts while the app is closed start them.
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

    var startsWhileClosed: Bool { authorization == .authorizedAlways }

    private var wanted = false

    func start() {
        wanted = true
        let onScreen = UIApplication.shared.applicationState == .active
        switch manager.authorizationStatus {
        case .notDetermined where onScreen:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse where onScreen:
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
            if self.wanted, !self.isRunning { self.start() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (error as? CLError)?.code == .denied else { return }
        Task { @MainActor in self.isRunning = false }
    }
}
