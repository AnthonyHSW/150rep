import Foundation
import Supabase

// MARK: - Row shapes

/// Rows written to `public.workout_sessions`. `user_id` is omitted deliberately: the column
/// defaults to `auth.uid()`, so the server decides ownership and a client can't claim a row
/// belongs to somebody else.
private struct WorkoutSessionRow: Encodable {
    let id: UUID
    let title: String
    let startTime: Date
    let endTime: Date?
    let status: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, title, status, notes
        case startTime = "start_time"
        case endTime = "end_time"
    }
}

/// Row written to `public.exercise_logs`.
private struct ExerciseLogRow: Encodable {
    let id: UUID
    let sessionId: UUID
    let exerciseId: String
    let name: String
    let primaryMuscle: String
    let imageName: String
    let orderIndex: Int
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, name, notes
        case sessionId = "session_id"
        case exerciseId = "exercise_id"
        case primaryMuscle = "primary_muscle"
        case imageName = "image_name"
        case orderIndex = "order_index"
    }
}

/// Row written to `public.exercise_sets`.
private struct ExerciseSetRow: Encodable {
    let id: UUID
    let exerciseLogId: UUID
    let setNumber: Int
    let setType: String
    let weight: Double
    let reps: Int
    let isCompleted: Bool
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, weight, reps
        case exerciseLogId = "exercise_log_id"
        case setNumber = "set_number"
        case setType = "set_type"
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
    }
}

// MARK: - Service

/// Pushes workouts — sessions, exercises, sets, and the photos hanging off them — to Supabase.
///
/// Offline-first, like `WorkoutPhotoSyncService`: a failed sync is an ordinary outcome, not an
/// error for the user to act on. Every write is an upsert keyed on an id the device already
/// owns, so re-running after a partial failure converges instead of duplicating.
@MainActor
struct WorkoutSyncService {

    /// Pushes one session and everything it contains.
    ///
    /// The order is fixed by the foreign keys — a child row inserted before its parent is
    /// rejected — which is also why photos go last rather than through their own entry point.
    static func sync(_ session: WorkoutSession, store: WorkoutStore) async throws {
        // Deletions first. A tombstone can name a row this pass is about to re-upsert only if
        // the row still exists locally, which can't happen; clearing them up front just keeps
        // the server from briefly holding rows the user already removed.
        try await flushDeletions(store: store)

        try await supabase
            .from(RemoteTable.workoutSessions.rawValue)
            .upsert(
                WorkoutSessionRow(
                    id: session.id,
                    title: session.title,
                    startTime: session.startTime,
                    endTime: session.endTime,
                    status: session.statusRaw,
                    notes: session.notes
                ),
                onConflict: "id"
            )
            .execute()

        let exercises = session.exercises.sorted { $0.orderIndex < $1.orderIndex }

        // Batched, unlike the photo uploads: those pair each row with a large binary that can
        // fail on its own, while these are plain rows and one round trip per table is enough.
        if !exercises.isEmpty {
            try await supabase
                .from(RemoteTable.exerciseLogs.rawValue)
                .upsert(
                    exercises.map {
                        ExerciseLogRow(
                            id: $0.id,
                            sessionId: session.id,
                            exerciseId: $0.exerciseId,
                            name: $0.name,
                            primaryMuscle: $0.primaryMuscle,
                            imageName: $0.imageName,
                            orderIndex: $0.orderIndex,
                            notes: $0.notes
                        )
                    },
                    onConflict: "id"
                )
                .execute()
        }

        let sets = exercises.flatMap { exerciseLog in
            exerciseLog.sets.map { set in
                ExerciseSetRow(
                    id: set.id,
                    exerciseLogId: exerciseLog.id,
                    setNumber: set.setNumber,
                    setType: set.setTypeRaw,
                    weight: set.weight,
                    reps: set.reps,
                    isCompleted: set.isCompleted,
                    completedAt: set.completedAt
                )
            }
        }

        if !sets.isEmpty {
            try await supabase
                .from(RemoteTable.exerciseSets.rawValue)
                .upsert(sets, onConflict: "id")
                .execute()
        }

        try await reconcile(session, exercises: exercises)

        // Stamped before the photos: the session and its contents are on the server at this
        // point, and photos carry their own `uploadedAt`. Stamping after would mean a failed
        // photo upload re-pushed every row next time for nothing.
        try store.markSynced(session)

        // Last, because `workout_photos.session_id` references the session row this pass just
        // created. Its own stamping means already-uploaded photos are skipped.
        try await WorkoutPhotoSyncService.syncPhotos(for: session, store: store)
    }

    /// Catches up everything outstanding: deletions first, then every session the server has
    /// never seen. Doubles as the one-time backfill, since workouts recorded before syncing
    /// existed have no `syncedAt` either.
    static func syncPending(store: WorkoutStore) async throws {
        try await flushDeletions(store: store)

        // Sequential on purpose. These are one user's rows over one connection, and running
        // them in order keeps each session's foreign key ordering intact without any
        // coordination between sessions.
        for session in try store.sessionsNeedingSync() {
            try await sync(session, store: store)
        }
    }

    /// Carries local deletions through to the server.
    static func flushDeletions(store: WorkoutStore) async throws {
        let pending = try store.pendingDeletions()
        guard !pending.isEmpty else { return }

        // Storage objects before rows. Reversed, a crash in between loses the only record of
        // the path and leaves the file in the bucket permanently unreferenced.
        let paths = pending.compactMap(\.storagePath)
        if !paths.isEmpty {
            try await supabase.storage
                .from(WorkoutPhotoSyncService.bucket)
                .remove(paths: paths)
        }

        for deletion in pending {
            guard let table = deletion.table else {
                // Written by a build that knew a table this one doesn't. Retrying forever is
                // worse than dropping it.
                try store.clearDeletion(deletion)
                continue
            }

            try await supabase
                .from(table.rawValue)
                .delete()
                .eq("id", value: deletion.id.uuidString)
                .execute()

            // Cleared only once the request lands, so an interrupted flush retries. Repeating
            // is safe: deleting an id that is already gone matches no rows and still succeeds.
            try store.clearDeletion(deletion)
        }
    }

    /// Clears server-side rows with no local counterpart.
    ///
    /// Tombstones are the real mechanism for deletions; this is the backstop for the case they
    /// can't cover — a reinstall or a reset container takes the tombstones with it. It only
    /// ever runs for sessions that still exist locally, so it can never catch a deleted
    /// session, which is exactly why it isn't a substitute.
    private static func reconcile(_ session: WorkoutSession, exercises: [ExerciseLog]) async throws {
        try await deleteRows(
            from: .exerciseLogs,
            whereColumn: "session_id",
            equals: session.id,
            keeping: exercises.map(\.id)
        )

        // Sets under a removed log cascade, but ones removed from a log that survived don't.
        for exerciseLog in exercises {
            try await deleteRows(
                from: .exerciseSets,
                whereColumn: "exercise_log_id",
                equals: exerciseLog.id,
                keeping: exerciseLog.sets.map(\.id)
            )
        }
    }

    private static func deleteRows(
        from table: RemoteTable,
        whereColumn column: String,
        equals parentId: UUID,
        keeping ids: [UUID]
    ) async throws {
        let scoped = supabase
            .from(table.rawValue)
            .delete()
            .eq(column, value: parentId.uuidString)

        guard !ids.isEmpty else {
            // An empty keep-list can't be expressed as `not.in.()` — PostgREST rejects the
            // empty list — and it means every remote child is stale anyway.
            try await scoped.execute()
            return
        }

        let keepList = ids.map { "\"\($0.uuidString)\"" }.joined(separator: ",")
        try await scoped
            .not("id", operator: .in, value: "(\(keepList))")
            .execute()
    }
}
