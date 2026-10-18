import CoreLocation

/// The physical fence a crowd report has to be inside to count.
///
/// This is duplicated on the backend on purpose. The copy here is only so the app can
/// refuse an obviously-bad report without a round trip and say *why* in plain words; the
/// backend's copy is the one that actually decides, because a client check is worth
/// nothing against anyone willing to call the API directly. If one of these numbers
/// changes, both have to change — the backend reads them from `ARC_LATITUDE`,
/// `ARC_LONGITUDE` and `ARC_GEOFENCE_RADIUS_M`.
enum ArcGeofence {
    /// The Anteater Recreation Center.
    static let center = CLLocation(latitude: 33.6487, longitude: -117.8276)

    /// Generous enough to cover the whole rec complex — the building, the fields and the
    /// walkways between them — rather than just the weight room, so someone standing
    /// outside the front door is still "here".
    static let radius: CLLocationDistance = 300

    /// A fix wider than this tells us too little to act on: half the fence, so a report
    /// that passes is at worst standing at the edge of the complex rather than across
    /// campus. Indoor GPS routinely lands in the 20–80 m range, which still passes.
    static let maximumAccuracy: CLLocationDistance = 150

    /// How old a fix may be and still describe where the reporter is standing now.
    /// `requestLocation()` is allowed to hand back a cached fix, and a half-hour-old one
    /// from the parking lot is exactly the report this check exists to reject.
    static let maximumFixAge: TimeInterval = 120

    /// Metres from the centre of the complex.
    static func distance(from location: CLLocation) -> CLLocationDistance {
        location.distance(from: center)
    }

    static func contains(_ location: CLLocation) -> Bool {
        distance(from: location) <= radius
    }
}
