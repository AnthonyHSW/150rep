import CoreLocation
import Foundation

/// Why a crowd report could not be proved to come from the Arc.
///
/// These are all user-facing: a report is refused only for a reason we can explain and
/// that the person can act on, either by changing a setting or by actually being there.
enum LocationGateError: LocalizedError, Equatable {
    /// Location is switched off for the app, or the system prompt was declined.
    case permissionNotGranted
    /// Blocked by the device itself (parental controls, MDM) — a setting the user may
    /// not be able to change, so the wording doesn't promise that they can.
    case permissionRestricted
    /// Location services answered, but with nothing usable.
    case fixUnavailable
    /// A fix arrived whose own error estimate is wider than `ArcGeofence.maximumAccuracy`.
    case fixTooInaccurate(CLLocationDistance)
    /// Only a stale cached fix was on offer, which says where the phone used to be.
    case fixTooOld
    /// A good fix, and it isn't at the Arc. `distance` is `nil` when this is the
    /// backend's verdict rather than ours, since it reports the refusal, not the maths.
    case outsideGeofence(distance: CLLocationDistance?)

    var errorDescription: String? {
        switch self {
        case .permissionNotGranted:
            return "Reports need your location so we can tell you're at the ARC. Turn it on in Settings."
        case .permissionRestricted:
            return "Location is restricted on this device, so reports can't be verified."
        case .fixUnavailable:
            return "Couldn't get your location. Try again in a moment."
        case .fixTooInaccurate:
            return "Your location is too rough to confirm you're at the ARC. Try again outside or near a window."
        case .fixTooOld:
            return "Couldn't get a current location. Try again in a moment."
        case .outsideGeofence:
            return "You have to be at the ARC to report how busy it is."
        }
    }

    /// Whether this is fixed in Settings rather than by moving or waiting — the UI offers
    /// a shortcut there only for these.
    var isPermissionProblem: Bool {
        switch self {
        case .permissionNotGranted, .permissionRestricted: return true
        case .fixUnavailable, .fixTooInaccurate, .fixTooOld, .outsideGeofence: return false
        }
    }
}

/// One-shot location lookups for the crowd-report gate.
///
/// Deliberately not a continuous location feed: nothing in the app needs to follow the
/// user around, and a report only has to be true at the moment it is submitted. Each
/// call asks for a single fix, checks it against `ArcGeofence`, and forgets it.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    /// How many times to ask again when the only fix on offer is a stale cached one.
    /// `requestLocation()` answers with the cache first and the live fix a beat later,
    /// so one retry is usually all it takes.
    private static let fixAttempts = 2

    private let manager = CLLocationManager()
    private var authorizationWaiters: [CheckedContinuation<CLAuthorizationStatus, Never>] = []
    private var fixWaiters: [CheckedContinuation<Result<CLLocation, Error>, Never>] = []

    private override init() {
        super.init()
        manager.delegate = self
        // Ten metres is far finer than a 300 m fence needs, and asking for the best
        // possible fix would keep the radio up longer for no gain in the answer.
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Current authorization, as the app should present it — `nil` while undecided.
    var isDenied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    /// A fresh fix that is close enough to the Arc to back a report, or an error saying
    /// which part of that failed. Prompts for permission the first time it is called.
    ///
    /// Passing this is necessary but not sufficient: the backend repeats the check on the
    /// coordinates it receives, because this one runs on the reporter's own device.
    func locationAtArc() async throws -> CLLocation {
        switch await resolvedAuthorization() {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        case .restricted:
            throw LocationGateError.permissionRestricted
        case .denied, .notDetermined:
            throw LocationGateError.permissionNotGranted
        @unknown default:
            throw LocationGateError.permissionNotGranted
        }

        let location = try await freshFix()

        // A negative accuracy means the fix is invalid, not that it is perfect.
        guard location.horizontalAccuracy >= 0 else {
            throw LocationGateError.fixUnavailable
        }
        guard location.horizontalAccuracy <= ArcGeofence.maximumAccuracy else {
            throw LocationGateError.fixTooInaccurate(location.horizontalAccuracy)
        }

        let distance = ArcGeofence.distance(from: location)
        guard distance <= ArcGeofence.radius else {
            throw LocationGateError.outsideGeofence(distance: distance)
        }

        return location
    }

    /// Settle on an authorization status, asking the user if they haven't been asked yet.
    private func resolvedAuthorization() async -> CLAuthorizationStatus {
        let status = manager.authorizationStatus
        guard status == .notDetermined else { return status }

        manager.requestWhenInUseAuthorization()

        return await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)
        }
    }

    /// A fix from the last `ArcGeofence.maximumFixAge`, retrying past cached answers.
    private func freshFix() async throws -> CLLocation {
        var lastStaleError: LocationGateError?

        for _ in 0..<Self.fixAttempts {
            let location = try await requestSingleFix()

            if Date().timeIntervalSince(location.timestamp) <= ArcGeofence.maximumFixAge {
                return location
            }
            lastStaleError = .fixTooOld
        }

        throw lastStaleError ?? LocationGateError.fixUnavailable
    }

    private func requestSingleFix() async throws -> CLLocation {
        let result: Result<CLLocation, Error> = await withCheckedContinuation { continuation in
            fixWaiters.append(continuation)
            manager.requestLocation()
        }
        return try result.get()
    }

    private func resumeFixWaiters(with result: Result<CLLocation, Error>) {
        let waiters = fixWaiters
        fixWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: result) }
    }

    // MARK: - CLLocationManagerDelegate

    // Callbacks land on the queue the manager was created on, which is the main queue
    // here, so the hop is an assertion rather than a dispatch.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            let status = manager.authorizationStatus
            // The prompt is still up; nothing has been decided yet.
            guard status != .notDetermined else { return }

            let waiters = authorizationWaiters
            authorizationWaiters.removeAll()
            for waiter in waiters { waiter.resume(returning: status) }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        MainActor.assumeIsolated {
            guard let location = locations.last else {
                resumeFixWaiters(with: .failure(LocationGateError.fixUnavailable))
                return
            }
            resumeFixWaiters(with: .success(location))
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        MainActor.assumeIsolated {
            // `kCLErrorLocationUnknown` is the transient "still looking" failure, and
            // `denied` arrives here when location services are off device-wide. Both are
            // reported as our own errors so the UI has one vocabulary to speak.
            let code = CLError.Code(rawValue: (error as NSError).code)
            let gateError: LocationGateError = code == .denied
                ? .permissionNotGranted
                : .fixUnavailable
            resumeFixWaiters(with: .failure(gateError))
        }
    }
}
