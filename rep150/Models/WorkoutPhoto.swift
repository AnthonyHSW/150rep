import Foundation
import SwiftData

@Model
final class WorkoutPhoto {
    @Attribute(.unique) var id: UUID

    /// Filename inside `Documents/WorkoutPhotos/`, deliberately not a full path: the app's
    /// container directory is reassigned between installs and OS upgrades, so an absolute
    /// path saved today can be stale tomorrow. Resolved against the directory at read time.
    var filename: String

    var createdAt: Date
    var orderIndex: Int

    /// Where the photo landed in Supabase Storage. Both stay `nil` until an upload succeeds,
    /// which is how a pending photo is told apart from a synced one — the app has to work
    /// offline, so "not uploaded yet" is a normal state rather than a failure.
    var storagePath: String?
    var remoteURL: String?
    var uploadedAt: Date?

    var workoutSession: WorkoutSession?

    /// Whether this photo still needs pushing to Supabase.
    var needsUpload: Bool { uploadedAt == nil }

    init(
        id: UUID = UUID(),
        filename: String,
        createdAt: Date = Date(),
        orderIndex: Int
    ) {
        self.id = id
        self.filename = filename
        self.createdAt = createdAt
        self.orderIndex = orderIndex
    }
}
