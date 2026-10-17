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
struct CrowdReportInsert: Encodable {
    let level: Int
}
