import Foundation
import SwiftData

/// The Postgres tables the app writes to. Named once so a tombstone can't point at a table
/// that doesn't exist.
enum RemoteTable: String, Codable, CaseIterable {
    case workoutSessions = "workout_sessions"
    case exerciseLogs = "exercise_logs"
    case exerciseSets = "exercise_sets"
    case workoutPhotos = "workout_photos"
}

/// A row deleted on this device that still needs deleting on the server.
///
/// A deletion can't be recovered by comparing local state against remote: once
/// `modelContext.delete` runs the object is gone, and a row that was deleted looks exactly
/// like one that never existed. Without a record that outlives it, any deletion made offline
/// would simply never reach the server. This is that record.
@Model
final class PendingDeletion {
    /// The deleted row's own id, which is its primary key server-side too.
    @Attribute(.unique) var id: UUID

    var tableRaw: String

    /// For photos, the Storage object to remove alongside the row. Storage sits outside the
    /// foreign key graph, so no cascade ever reaches it.
    var storagePath: String?

    var requestedAt: Date

    /// `nil` only if a tombstone was written by a build that knew a table this one doesn't.
    var table: RemoteTable? { RemoteTable(rawValue: tableRaw) }

    init(
        id: UUID,
        table: RemoteTable,
        storagePath: String? = nil,
        requestedAt: Date = Date()
    ) {
        self.id = id
        self.tableRaw = table.rawValue
        self.storagePath = storagePath
        self.requestedAt = requestedAt
    }
}
