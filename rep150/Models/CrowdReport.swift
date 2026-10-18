import Foundation

/// A single "how busy is it" report, stored in the Supabase `crowd_reports` table.
struct CrowdReport: Codable {
    let id: UUID?
    let level: Int
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case level
        case createdAt = "created_at"
    }
}

/// Payload for submitting a new report; `id`/`created_at` are assigned by the database.
///
/// The coordinates are not stored as part of the report — the backend uses them once, to
/// check the reporter is inside the Arc's geofence, and keeps only the verdict. They are
/// sent on every submit because the check is the backend's to make: the app runs the same
/// check first, but only so it can refuse early and explain why.
struct CrowdReportInsert: Encodable {
    let level: Int
    let latitude: Double
    let longitude: Double
    /// The fix's own horizontal error estimate, in metres, so the backend can apply the
    /// same "too rough to act on" floor the app does instead of trusting a vague fix.
    let accuracyMeters: Double
    /// When the fix was taken — `CLLocation.timestamp`, not the moment of the request. The
    /// backend refuses anything older than two minutes: coordinates prove where the device
    /// was, and without this they don't say when, so a cached fix from this morning would
    /// otherwise pass the radius check from anywhere.
    let locationTimestamp: Date

    enum CodingKeys: String, CodingKey {
        case level
        case latitude
        case longitude
        case accuracyMeters = "accuracy_m"
        case locationTimestamp = "location_timestamp"
    }
}

/// Response body from `GET /v1/crowd-level`.
///
/// `level` is nullable: the backend returns `null` for it whenever there is nothing to
/// average, so it has to be optional here or an empty gym fails to decode at all.
struct CrowdLevelResponse: Decodable {
    let level: Double?
    let reportCount: Int

    enum CodingKeys: String, CodingKey {
        case level
        case reportCount = "report_count"
    }
}
