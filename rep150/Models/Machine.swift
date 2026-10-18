import Foundation

/// A gym machine and its latest reported status, as returned by `GET /v1/machines`.
struct Machine: Identifiable, Decodable, Equatable {
    let id: Int
    let name: String
    /// Optional server-side — a machine can be added before anyone says which room it's in.
    let location: String?
    let isInUse: Bool
    /// `nil` until somebody first reports on this machine, which is not the same as having
    /// been reported free. The UI has to tell those apart or an untouched machine looks
    /// like a confirmed-available one.
    let statusUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, location
        case isInUse = "is_in_use"
        case statusUpdatedAt = "status_updated_at"
    }

    /// Whether anyone has ever reported on this machine.
    var hasBeenReported: Bool { statusUpdatedAt != nil }
}

/// Body for `POST /v1/machines`.
struct MachineCreate: Encodable {
    let name: String
    let location: String?
}

/// Body for `PUT /v1/machines/{id}/status`.
struct MachineStatusUpdate: Encodable {
    let isInUse: Bool

    enum CodingKeys: String, CodingKey {
        case isInUse = "is_in_use"
    }
}
