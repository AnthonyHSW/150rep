import Foundation
import SwiftData

/// Owns every read and write of the workout model graph.
///
/// Mutations used to call `try? modelContext.save()` inline at each site, which made a
/// failed save indistinguishable from a successful one — the user would finish a workout,
/// see it dismiss, and lose it. Routing persistence through one type gives a single place
/// to decide what a stored session looks like and a single place for failures to surface.
/// Stateless by design — it holds nothing but the context, so callers can make one wherever
/// they need it rather than threading a single instance through the view tree.
@MainActor
struct WorkoutStore {
    enum StoreError: LocalizedError {
        case saveFailed(Error)
        case fetchFailed(Error)

        var errorDescription: String? {
            switch self {
            case .saveFailed(let error):
                "Couldn't save your workout: \(error.localizedDescription)"
            case .fetchFailed(let error):
                "Couldn't load your workouts: \(error.localizedDescription)"
            }
        }
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Session lifecycle

    /// Starts a workout — or hands back the one already in flight.
    ///
    /// Returning the existing session instead of inserting a second is what keeps Finish
    /// working. Only one workout can be happening at a time, but nothing stopped Start from
    /// being tapped while a session was open, and each tap added another `.active` row. With
    /// several in the store, finishing one only promotes the next into the In Progress
    /// section — same default title, same start-time formatting — so the workout appears not
    /// to have finished at all.
    ///
    /// `title` applies only to a genuinely new session; resuming keeps whatever the workout
    /// was already called, including a name the user chose.
    func startSession(title: String = WorkoutSession.defaultTitle()) throws -> WorkoutSession {
        if let inFlight = try interruptedSession() {
            return inFlight
        }

        let session = WorkoutSession(title: title)
        modelContext.insert(session)
        try save()
        return session
    }

    /// The session still in flight, if there is one.
    ///
    /// Nothing moves a session off `.active` except finishing or discarding it, so exiting a
    /// workout — or a crash or force-quit mid-workout — leaves one behind for the Workouts
    /// list to offer under In Progress. Without this the session is stranded: still in the
    /// store, invisible to the user, and never counted as history.
    func interruptedSession() throws -> WorkoutSession? {
        let activeRaw = SessionStatus.active.rawValue
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.statusRaw == activeRaw },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            throw StoreError.fetchFailed(error)
        }
    }

    /// Completes a session and writes it to history.
    ///
    /// Incomplete sets are dropped by default: the set rows sitting in the UI when Finish is
    /// tapped are a data-entry scaffold, not work that happened, and keeping them would mean
    /// history and the `PREVIOUS` column disagree about what a workout contained.
    func finish(_ session: WorkoutSession, prunesIncompleteWork: Bool = true) throws {
        // Skip pruning when nothing was ticked off: it would strip every exercise and leave
        // a hollow entry in History, which reads as Finish having failed. Keeping what the
        // user entered is the more faithful record of a session they chose to finish.
        if prunesIncompleteWork && session.totalCompletedSets > 0 {
            pruneIncompleteWork(in: session)
        }
        normalizeExerciseOrder(in: session)
        session.endTime = Date()
        session.status = .completed
        try save()
    }

    /// Deletes a session outright. The cascade rules on `WorkoutSession.exercises` and
    /// `ExerciseLog.sets` take its exercises and sets with it.
    func discard(_ session: WorkoutSession) throws {
        // The photo rows cascade, but the JPEGs they name sit in the sandbox where no delete
        // rule reaches them. Clear the files first or discarding a workout leaks them forever.
        for photo in session.photos {
            WorkoutPhotoFileManager.shared.deleteImage(filename: photo.filename)
            // The remote mirror of the same problem: the row goes with the session, but the
            // Storage object is outside the foreign keys, so each uploaded file has to be
            // named individually or it is stranded in the bucket.
            recordDeletion(
                of: photo.id,
                in: .workoutPhotos,
                storagePath: photo.storagePath,
                ifSynced: photo.uploadedAt != nil
            )
        }

        // Only the session itself is recorded — its exercises, sets, and photo rows all
        // cascade from it server-side.
        recordDeletion(of: session.id, in: .workoutSessions, ifSynced: !session.needsSync)

        // Deliberately no `status = .discarded` write first — the object is being deleted,
        // so that write persists nothing and only muddies what the status means.
        modelContext.delete(session)
        try save()
    }

    // MARK: - History

    func completedSessions(limit: Int? = nil) throws -> [WorkoutSession] {
        let completedRaw = SessionStatus.completed.rawValue
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.statusRaw == completedRaw },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        if let limit {
            descriptor.fetchLimit = limit
        }

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw StoreError.fetchFailed(error)
        }
    }

    func previousSets(forExerciseId exerciseId: String) -> [ExerciseSet] {
        HistoricalDataService.fetchPreviousSets(for: exerciseId, context: modelContext)
    }

    // MARK: - Contents

    func addExercise(_ exercise: Exercise, to session: WorkoutSession) throws {
        let exerciseLog = ExerciseLog(
            exerciseId: exercise.id,
            name: exercise.name,
            primaryMuscle: exercise.primaryMuscle,
            imageName: exercise.imageName,
            orderIndex: session.exercises.count
        )

        // Seed the first set from the last time this exercise was logged, so the user is
        // adjusting a sensible starting point instead of typing from zero.
        let previous = previousSets(forExerciseId: exercise.id).first
        exerciseLog.sets.append(
            ExerciseSet(setNumber: 1, weight: previous?.weight ?? 0, reps: previous?.reps ?? 0)
        )

        exerciseLog.workoutSession = session
        session.exercises.append(exerciseLog)
        try save()
    }

    func removeExercise(_ exerciseLog: ExerciseLog, from session: WorkoutSession) throws {
        // Its sets cascade from the log, so they need no tombstones of their own.
        recordDeletion(of: exerciseLog.id, in: .exerciseLogs, ifSynced: !session.needsSync)
        session.exercises.removeAll { $0.id == exerciseLog.id }
        modelContext.delete(exerciseLog)
        // Removal leaves a hole in the order (0, 2, 3); close it so stored indices keep
        // matching the positions the reorder UI works in.
        normalizeExerciseOrder(in: session)
        try save()
    }

    func addSet(to exerciseLog: ExerciseLog) throws {
        let lastSet = exerciseLog.sets.max { $0.setNumber < $1.setNumber }
        let newSet = ExerciseSet(
            setNumber: (lastSet?.setNumber ?? 0) + 1,
            weight: lastSet?.weight ?? 0,
            reps: lastSet?.reps ?? 0
        )
        exerciseLog.sets.append(newSet)
        try save()
    }

    func removeSet(_ set: ExerciseSet, from exerciseLog: ExerciseLog) throws {
        recordDeletion(
            of: set.id,
            in: .exerciseSets,
            ifSynced: exerciseLog.workoutSession.map { !$0.needsSync } ?? false
        )
        exerciseLog.sets.removeAll { $0.id == set.id }
        modelContext.delete(set)
        renumberSets(in: exerciseLog)
        try save()
    }

    // MARK: - Photos

    /// Writes `data` into the sandbox and links a photo row to `session`.
    ///
    /// Throws rather than failing quietly so the caller can tell the user a photo didn't
    /// save — silently dropping one looks identical to the picker misbehaving. The cap is
    /// enforced here as well as in the picker, since the picker's limit is only advisory
    /// once several selections are being processed in a row.
    @discardableResult
    func addPhoto(data: Data, to session: WorkoutSession) throws -> WorkoutPhoto? {
        guard session.canAddPhoto else { return nil }

        let filename = try WorkoutPhotoFileManager.shared.saveImage(data: data)
        let photo = WorkoutPhoto(
            filename: filename,
            orderIndex: (session.photos.map(\.orderIndex).max() ?? -1) + 1
        )
        photo.workoutSession = session

        do {
            try save()
        } catch {
            // The row never landed, so the file it names is unreachable — don't leave it
            // behind taking up space.
            WorkoutPhotoFileManager.shared.deleteImage(filename: filename)
            throw error
        }
        return photo
    }

    func removePhoto(_ photo: WorkoutPhoto, from session: WorkoutSession) throws {
        WorkoutPhotoFileManager.shared.deleteImage(filename: photo.filename)
        recordDeletion(
            of: photo.id,
            in: .workoutPhotos,
            storagePath: photo.storagePath,
            ifSynced: photo.uploadedAt != nil
        )
        session.photos.removeAll { $0.id == photo.id }
        modelContext.delete(photo)
        normalizePhotoOrder(in: session)
        try save()
    }

    /// Rewrites photo `orderIndex` to `0..<n`, closing the gap a deletion leaves behind.
    func normalizePhotoOrder(in session: WorkoutSession) {
        for (index, photo) in session.orderedPhotos.enumerated() {
            photo.orderIndex = index
        }
    }

    /// Rewrites `orderIndex` to `0..<n` in the current sort order.
    func normalizeExerciseOrder(in session: WorkoutSession) {
        for (index, exercise) in session.exercises.sorted(by: { $0.orderIndex < $1.orderIndex }).enumerated() {
            exercise.orderIndex = index
        }
    }

    // MARK: - Sync support

    /// Sessions the server has never seen, oldest first.
    ///
    /// Active sessions are excluded: one still in progress changes on every tap, and pushing
    /// each edit would spend requests on a workout that isn't finished being written.
    func sessionsNeedingSync() throws -> [WorkoutSession] {
        let activeRaw = SessionStatus.active.rawValue
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.syncedAt == nil && $0.statusRaw != activeRaw },
            sortBy: [SortDescriptor(\.startTime)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw StoreError.fetchFailed(error)
        }
    }

    /// Deletions waiting to reach the server, in the order they were made.
    func pendingDeletions() throws -> [PendingDeletion] {
        let descriptor = FetchDescriptor<PendingDeletion>(
            sortBy: [SortDescriptor(\.requestedAt)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw StoreError.fetchFailed(error)
        }
    }

    /// Drops a tombstone once its deletion has landed server-side.
    func clearDeletion(_ deletion: PendingDeletion) throws {
        modelContext.delete(deletion)
        try save()
    }

    func markSynced(_ session: WorkoutSession) throws {
        session.syncedAt = Date()
        try save()
    }

    /// Notes that `id` needs deleting server-side — but only if the server ever had it.
    /// A row that was never uploaded needs no delete request, and enqueuing one would mean
    /// every offline-only workout left a pointless round trip behind it.
    private func recordDeletion(
        of id: UUID,
        in table: RemoteTable,
        storagePath: String? = nil,
        ifSynced wasSynced: Bool
    ) {
        guard wasSynced else { return }
        modelContext.insert(
            PendingDeletion(id: id, table: table, storagePath: storagePath)
        )
    }

    // MARK: - Persistence

    func save() throws {
        guard modelContext.hasChanges else { return }
        do {
            try modelContext.save()
        } catch {
            throw StoreError.saveFailed(error)
        }
    }

    // MARK: - Cleanup

    private func pruneIncompleteWork(in session: WorkoutSession) {
        // Normally a no-op for sync: this runs inside `finish`, before a session has ever
        // been uploaded, so there is nothing on the server to delete. Guarded all the same,
        // because a session that is finished twice would otherwise drop rows server-side
        // with nothing left to say they went.
        let wasSynced = !session.needsSync

        for exerciseLog in session.exercises {
            let incomplete = exerciseLog.sets.filter { !$0.isCompleted }
            guard !incomplete.isEmpty else { continue }
            exerciseLog.sets.removeAll { !$0.isCompleted }
            for set in incomplete {
                recordDeletion(of: set.id, in: .exerciseSets, ifSynced: wasSynced)
                modelContext.delete(set)
            }
            renumberSets(in: exerciseLog)
        }

        // An exercise with nothing completed was never actually performed.
        let emptyLogs = session.exercises.filter { $0.sets.isEmpty }
        guard !emptyLogs.isEmpty else { return }
        session.exercises.removeAll { $0.sets.isEmpty }
        for exerciseLog in emptyLogs {
            recordDeletion(of: exerciseLog.id, in: .exerciseLogs, ifSynced: wasSynced)
            modelContext.delete(exerciseLog)
        }
    }

    /// Closes gaps in set numbering so a stored exercise reads 1, 2, 3 rather than 1, 3, 4.
    private func renumberSets(in exerciseLog: ExerciseLog) {
        for (index, set) in exerciseLog.sets.sorted(by: { $0.setNumber < $1.setNumber }).enumerated() {
            set.setNumber = index + 1
        }
    }
}
