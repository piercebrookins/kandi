import CoreLocation
import Foundation

@MainActor
final class SafetyBackgroundMonitor: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private(set) var isActive: Bool = false

    private var supportsBackgroundLocation: Bool {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        return modes.contains("location")
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = 200
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.allowsBackgroundLocationUpdates = false
    }

    func start() {
        guard CLLocationManager.locationServicesEnabled() else { return }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            if supportsBackgroundLocation {
                locationManager.requestAlwaysAuthorization()
            } else {
                locationManager.requestWhenInUseAuthorization()
            }
        case .authorizedAlways:
            locationManager.allowsBackgroundLocationUpdates = supportsBackgroundLocation
            locationManager.startUpdatingLocation()
            isActive = true
        case .authorizedWhenInUse:
            if supportsBackgroundLocation {
                locationManager.requestAlwaysAuthorization()
            } else {
                locationManager.allowsBackgroundLocationUpdates = false
                locationManager.startUpdatingLocation()
                isActive = true
            }
        case .restricted, .denied:
            isActive = false
        @unknown default:
            isActive = false
        }
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        isActive = false
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways:
                manager.allowsBackgroundLocationUpdates = self.supportsBackgroundLocation
                manager.startUpdatingLocation()
                self.isActive = true
            case .authorizedWhenInUse:
                manager.allowsBackgroundLocationUpdates = false
                manager.startUpdatingLocation()
                self.isActive = true
            case .restricted, .denied:
                manager.stopUpdatingLocation()
                self.isActive = false
            case .notDetermined:
                break
            @unknown default:
                self.isActive = false
            }
        }
    }
}
