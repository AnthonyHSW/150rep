import Foundation
import Supabase

/// Row written to `public.workout_photos`.
private struct WorkoutPhotoRow: Encodable {
    let id: UUID
    let sessionId: UUID
    let storagePath: String
    let publicUrl: String
    let orderIndex: Int

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case storagePath = "storage_path"
        case publicUrl = "public_url"
        case orderIndex = "order_index"
    }
}

/// Pushes locally stored workout photos to Supabase Storage and records them in Postgres.
///
/// Offline-first: the app is usable with no connection, and a failed sync is expected rather
/// than exceptional. Nothing here mutates local state beyond stamping what has been uploaded,
/// so an interrupted run just leaves the remaining photos pending for the next attempt.
@MainActor
struct WorkoutPhotoSyncService {
    static let bucket = "workout-photos"

    /// Uploads every photo on `session` that hasn't synced yet.
    ///
    /// Each photo is uploaded and recorded individually: a batch insert would make one bad
    /// photo lose the whole set, and re-running after a partial failure would duplicate the
    /// rows that did land. Returns the number newly uploaded.
    @discardableResult
    static func syncPhotos(for session: WorkoutSession, store: WorkoutStore) async throws -> Int {
        let pending = session.orderedPhotos.filter(\.needsUpload)
        guard !pending.isEmpty else { return 0 }

        // Anonymous sessions count — this just needs a user id to scope the storage path.
        let userId = try await AuthService.currentUserId()
        var uploaded = 0

        for photo in pending {
            let fileURL = try WorkoutPhotoFileManager.shared.url(for: photo.filename)
            guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
                // The row outlived its file; skip it rather than failing the whole sync.
                continue
            }

            let path = "\(userId.uuidString)/\(session.id.uuidString)/\(photo.id.uuidString).jpg"

            // Uploading from the file URL streams it off disk instead of reading the whole
            // JPEG into memory, and avoids a second lossy re-encode of an already-compressed
            // image.
            try await supabase.storage
                .from(bucket)
                .upload(path, fileURL: fileURL, options: FileOptions(contentType: "image/jpeg"))

            let publicURL = try supabase.storage.from(bucket).getPublicURL(path: path)

            try await supabase
                .from("workout_photos")
                .insert(
                    WorkoutPhotoRow(
                        id: photo.id,
                        sessionId: session.id,
                        storagePath: path,
                        publicUrl: publicURL.absoluteString,
                        orderIndex: photo.orderIndex
                    )
                )
                .execute()

            // Stamped only after both the upload and the row succeed, so a crash in between
            // leaves the photo pending and the next sync retries it.
            photo.storagePath = path
            photo.remoteURL = publicURL.absoluteString
            photo.uploadedAt = Date()
            try store.save()

            uploaded += 1
        }

        return uploaded
    }
}
