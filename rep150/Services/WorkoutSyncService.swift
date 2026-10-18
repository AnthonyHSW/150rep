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
    /// Non-nil only while the workout is open on screen; see `publishLiveProgress`. A null
    /// here is what takes a workout back out of everyone else's Active Workouts list.
    let lastActiveAt: Date?
    /// The owner's own Google name and picture, denormalized so a watcher can see whose
    /// workout this is without reading auth.users.
    let ownerName: String?
    let ownerAvatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, title, status, notes
        case startTime = "start_time"
        case endTime = "end_time"
        case lastActiveAt = "last_active_at"
        case ownerName = "owner_name"
        case ownerAvatarUrl = "owner_avatar_url"
    }

    /// Written by hand because the synthesized version uses `encodeIfPresent`, which drops
    /// nil fields from the payload entirely — and an omitted column in an upsert leaves
    /// whatever the server already had. Every nil here has to travel as an explicit null:
    /// it is how a workout stops being live, and how a cleared note or end time clears.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(status, forKey: .status)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(notes, forKey: .notes)
        try container.encode(lastActiveAt, forKey: .lastActiveAt)
        try container.encode(ownerName, forKey: .ownerName)
        try container.encode(ownerAvatarUrl, forKey: .ownerAvatarUrl)
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
    let isCardio: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, notes
        case sessionId = "session_id"
        case exerciseId = "exercise_id"
        case primaryMuscle = "primary_muscle"
        case imageName = "image_name"
        case orderIndex = "order_index"
        case isCardio = "is_cardio"
    }
}

/// Row written to `public.exercise_sets`.
///
/// Weight/reps and duration are mutually exclusive: a time-based set sends the first pair as
/// null and carries `duration_seconds`, and a weight set does the reverse. Nulls rather than
/// zeros, because "0 kg × 0 reps" reads as a logged set left empty, which is a different claim
/// from "this set isn't measured that way".
private struct ExerciseSetRow: Encodable {
    let id: UUID
    let exerciseLogId: UUID
    let setNumber: Int
    let setType: String
    let weight: Double?
    let reps: Int?
    let durationSeconds: Int?
    let isCompleted: Bool
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, weight, reps
        case exerciseLogId = "exercise_log_id"
        case setNumber = "set_number"
        case setType = "set_type"
        case durationSeconds = "duration_seconds"
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
    }

    /// Hand-written for the same reason as `WorkoutSessionRow`: the synthesized version uses
    /// `encodeIfPresent`, and an omitted column in an upsert leaves whatever the server
    /// already had. These nulls have to travel — they are how an exercise corrected from
    /// weight to time stops reporting the weight it used to have.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(exerciseLogId, forKey: .exerciseLogId)
        try container.encode(setNumber, forKey: .setNumber)
        try container.encode(setType, forKey: .setType)
        try container.encode(weight, forKey: .weight)
        try container.encode(reps, forKey: .reps)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(completedAt, forKey: .completedAt)
    }
}

/// Clears (or sets) just the live heartbeat on an existing session row.
///
/// A narrow update rather than an upsert through `WorkoutSessionRow`: ending a broadcast
/// shouldn't depend on the local session still agreeing with the server about its title or
/// its sets, and this way it is one column and one round trip. Encoded by hand for the same
/// reason as that type — `encodeIfPresent` would drop the nil and the update would be empty.
private struct LiveStampUpdate: Encodable {
    let lastActiveAt: Date?

    enum CodingKeys: String, CodingKey {
        case lastActiveAt = "last_active_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lastActiveAt, forKey: .lastActiveAt)
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

        // `lastActiveAt: nil` because this is the settled push — the workout is finished, or
        // being corrected afterwards. Only `publishLiveProgress` stamps a session live, so a
        // workout can never be left broadcasting by the sync that put it in history.
        let exercises = try await pushRows(session, lastActiveAt: nil)

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

    // MARK: - Live broadcast

    /// Pushes an open workout and stamps it live, so it appears under Active Workouts for
    /// everyone else.
    ///
    /// Called when the workout screen opens and on a timer while it stays open, which is
    /// what `last_active_at` is a record of — the heartbeat, not the edit. That matters for
    /// the case `WorkoutStore.sessionsNeedingSync` already calls out: a live workout changes
    /// on every tap, and pushing each one would spend a request on a workout that isn't
    /// finished being written. A fixed interval is what makes watching affordable.
    ///
    /// Lighter than `sync` on purpose: no photos and no deletion flush. Photos are not
    /// served to watchers at all (no policy grants them), and the deletion queue is the
    /// settled sync's business — neither belongs on something that runs every minute.
    static func publishLiveProgress(_ session: WorkoutSession, store: WorkoutStore) async throws {
        let exercises = try await pushRows(session, lastActiveAt: Date())
        try await reconcile(session, exercises: exercises)

        // Stamped synced even though the photos haven't gone up, because `syncedAt` is also
        // what `WorkoutStore.recordDeletion` consults: without it, discarding this workout
        // would leave no tombstone and the server would keep serving a session the owner
        // threw away. The photos are not lost — finishing the workout runs the full sync.
        try store.markSynced(session)
    }

    /// Takes a workout back out of the live feed without finishing it.
    ///
    /// Exiting leaves a session `.active` so In Progress can offer it to resume, which means
    /// status alone can't distinguish "being done right now" from "abandoned an hour ago" —
    /// clearing the heartbeat is what does. The server's window would age it out anyway;
    /// this makes it immediate, so leaving the screen stops the broadcast then and there.
    static func endLiveProgress(_ session: WorkoutSession) async throws {
        // A session the server never saw has no row to clear, and the update would match
        // nothing.
        guard !session.needsSync else { return }

        try await supabase
            .from(RemoteTable.workoutSessions.rawValue)
            .update(LiveStampUpdate(lastActiveAt: nil))
            .eq("id", value: session.id.uuidString)
            .execute()
    }

    /// Upserts the session, its exercises, and its sets, returning the exercises in order so
    /// the caller can reconcile against them. The one place either push path writes rows,
    /// so the live broadcast and the settled sync can't drift into disagreeing about shape.
    @discardableResult
    private static func pushRows(
        _ session: WorkoutSession,
        lastActiveAt: Date?
    ) async throws -> [ExerciseLog] {
        let account = AuthService.shared.account

        try await supabase
            .from(RemoteTable.workoutSessions.rawValue)
            .upsert(
                WorkoutSessionRow(
                    id: session.id,
                    title: session.title,
                    startTime: session.startTime,
                    endTime: session.endTime,
                    status: session.statusRaw,
                    notes: session.notes,
                    lastActiveAt: lastActiveAt,
                    ownerName: account?.displayName,
                    ownerAvatarUrl: account?.avatarURL?.absoluteString
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
                            notes: $0.notes,
                            isCardio: $0.isCardio
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
                    weight: exerciseLog.isCardio ? nil : set.weight,
                    reps: exerciseLog.isCardio ? nil : set.reps,
                    durationSeconds: exerciseLog.isCardio ? set.durationSeconds : nil,
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

        return exercises
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
