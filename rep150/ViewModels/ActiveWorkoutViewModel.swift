import Foundation
import SwiftData
import SwiftUI
import UIKit

@Observable
@MainActor
final class ActiveWorkoutViewModel: Identifiable {
    /// What the workout screen is being used for. The editing case exists so a finished
    /// workout can be reopened and corrected in the same UI, minus anything that only makes
    /// sense while it's happening — the clocks.
    enum Mode {
        /// A workout happening now: the duration counts up and finishing a set starts a rest
        /// timer.
        case live
        /// A completed workout being reviewed or corrected. Its duration is already settled,
        /// so nothing ticks.
        case editing
    }

    /// Held as a plain value rather than read off `activeSession`, so `Identifiable` is
    /// satisfied without the identity itself becoming main-actor isolated.
    nonisolated let id: UUID

    let mode: Mode

    var activeSession: WorkoutSession
    var elapsedTime: TimeInterval = 0
    var restElapsed: Int = 0
    var restTargetDuration: Int = 90
    var isRestTimerRunning: Bool = false

    /// Set when a write to the store fails, so the UI can tell the user their work didn't
    /// save instead of silently carrying on.
    var persistenceErrorMessage: String?

    /// How often an open workout is republished for watchers. A minute is slow enough that
    /// watching costs one request per lifter per minute, and fast enough that a set ticked
    /// off shows up while the person watching is still looking at the same screen.
    static let liveBroadcastInterval: TimeInterval = 60

    private let store: WorkoutStore
    private var sessionTimer: Timer?
    private var restTimer: Timer?
    private var liveBroadcastTimer: Timer?
    /// The heartbeat request currently in flight, if any. Held so ending the broadcast can
    /// wait for it instead of racing it.
    private var liveBroadcastTask: Task<Void, Never>?
    private var hasNotifiedRestTarget = false

    init(session: WorkoutSession, store: WorkoutStore, mode: Mode = .live) {
        self.id = session.id
        self.activeSession = session
        self.store = store
        self.mode = mode

        switch mode {
        case .live:
            startSessionTimer()
            startLiveBroadcast()
        case .editing:
            // Already finished, so the duration is a fact rather than something to count.
            elapsedTime = session.duration
        }
    }

    func startSessionTimer() {
        guard mode == .live else { return }
        elapsedTime = Date().timeIntervalSince(activeSession.startTime)
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.elapsedTime = Date().timeIntervalSince(self.activeSession.startTime)
            }
        }
    }

    // MARK: - Live broadcast

    /// Starts publishing this workout for other users to watch, immediately and then on a
    /// timer. Live mode only: a finished workout being corrected is not happening now, and
    /// broadcasting it would put a workout from last Tuesday in everyone's Active Workouts.
    func startLiveBroadcast() {
        guard mode == .live, liveBroadcastTimer == nil else { return }

        // Published straight away, not on the first tick: otherwise a workout nobody adds an
        // exercise to for a minute isn't visible to anyone for that minute.
        publishLiveProgress()

        liveBroadcastTimer = Timer.scheduledTimer(
            withTimeInterval: Self.liveBroadcastInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.publishLiveProgress()
            }
        }
    }

    /// Fire-and-forget, for the same reason `syncWorkout` is: the workout is already saved
    /// locally, and a heartbeat that doesn't land costs the lifter nothing — it only means
    /// watchers see this workout age out until the next one goes through.
    ///
    /// Captures the session and store rather than `self` so a request in flight isn't tied
    /// to this screen still existing.
    private func publishLiveProgress() {
        let session = activeSession

        liveBroadcastTask = Task { [store] in
            do {
                try await WorkoutSyncService.publishLiveProgress(session, store: store)
            } catch {
                print("Live workout broadcast deferred: \(error)")
            }
        }
    }

    /// Clears the heartbeat so watchers stop seeing this workout, without touching its
    /// status — it stays `.active` locally so In Progress can still offer it to resume.
    private func endLiveBroadcast() {
        guard mode == .live else { return }
        let session = activeSession
        let inFlight = liveBroadcastTask
        liveBroadcastTask = nil

        Task {
            // Wait out a heartbeat that was already on its way. Invalidating the timer stops
            // new ones, but a request mid-flight carries a fresh timestamp, and landing after
            // the clear would put the workout straight back in everyone's feed.
            await inFlight?.value

            do {
                try await WorkoutSyncService.endLiveProgress(session)
            } catch {
                // The server's live window ages the workout out on its own, so a failure
                // here delays the broadcast ending rather than leaving it running forever.
                print("Live workout broadcast end deferred: \(error)")
            }
        }
    }

    // MARK: - Sets

    func toggleSetCompletion(_ set: ExerciseSet) {
        set.isCompleted.toggle()
        set.completedAt = set.isCompleted ? Date() : nil
        persist()

        if set.isCompleted {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            // Correcting a past workout shouldn't start a rest countdown for a rest that
            // happened days ago.
            if mode == .live {
                startRestTimer()
            }
        }
    }

    func addSet(to exercise: ExerciseLog) {
        persist { try store.addSet(to: exercise) }
    }

    func removeSet(_ set: ExerciseSet, from exercise: ExerciseLog) {
        persist { try store.removeSet(set, from: exercise) }
    }

    func previousSets(for exercise: ExerciseLog) -> [ExerciseSet] {
        store.previousSets(forExerciseId: exercise.exerciseId)
    }

    // MARK: - Exercises

    var orderedExercises: [ExerciseLog] {
        activeSession.exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    func addExercise(_ exercise: Exercise) {
        persist { try store.addExercise(exercise, to: activeSession) }
    }

    func removeExercise(_ exercise: ExerciseLog) {
        persist { try store.removeExercise(exercise, from: activeSession) }
    }

    /// Moves `draggedId` so it ends up at `targetIndex` among the *other* exercises
    /// (i.e. `targetIndex` is the position within the list once the dragged exercise
    /// has been removed from it).
    ///
    /// Reordering is index-based: a drag only ever asks for a new position, never for
    /// a swap with a specific neighbour. Pass `persist: false` while a drag is in flight
    /// and call `commitExerciseOrder()` once it ends, so a drag across several cards
    /// doesn't write to the store on every boundary it crosses.
    func moveExercise(draggedId: UUID, toIndex targetIndex: Int, persist shouldPersist: Bool = true) {
        var ordered = orderedExercises
        guard let sourceIndex = ordered.firstIndex(where: { $0.id == draggedId }) else { return }

        let moved = ordered.remove(at: sourceIndex)
        let clampedIndex = min(max(targetIndex, 0), ordered.count)
        guard clampedIndex != sourceIndex else { return }
        ordered.insert(moved, at: clampedIndex)

        withAnimation(.snappy) {
            for (index, exercise) in ordered.enumerated() {
                exercise.orderIndex = index
            }
        }

        if shouldPersist {
            persist()
        }
    }

    func commitExerciseOrder() {
        persist()
    }

    // MARK: - Rest timer

    func startRestTimer() {
        restElapsed = 0
        hasNotifiedRestTarget = false
        isRestTimerRunning = true
        restTimer?.invalidate()

        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.restElapsed += 1
                if !self.hasNotifiedRestTarget && self.restElapsed >= self.restTargetDuration {
                    self.hasNotifiedRestTarget = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }

    func setRestTarget(_ seconds: Int) {
        restTargetDuration = seconds
        if isRestTimerRunning && restElapsed < seconds {
            hasNotifiedRestTarget = false
        }
    }

    func skipRest() {
        restTimer?.invalidate()
        isRestTimerRunning = false
        restElapsed = 0
    }

    // MARK: - Finishing

    /// Writes the session to history. Returns `false` if the save failed, so the caller can
    /// keep the workout on screen rather than dismissing work that was never stored.
    func finishWorkout() -> Bool {
        stopTimers()
        guard persist({ try store.finish(activeSession) }) else {
            // The workout is still live and the user is still in it — let the timers run on
            // so they can retry Finish, and keep it in everyone else's Active Workouts,
            // because it hasn't finished.
            startSessionTimer()
            startLiveBroadcast()
            return false
        }
        return true
    }

    /// Pushes this session to Supabase once it's been settled — the workout itself, its
    /// exercises and sets, and then its photos.
    ///
    /// Deliberately fire-and-forget: syncing is best-effort, and the app has to stay usable
    /// offline, so anything that doesn't land stays pending for a later attempt rather than
    /// holding the user on a finished workout. Captures the session and store instead of
    /// `self` so the upload outlives this screen being dismissed.
    ///
    /// No pending-work guard the way the photo-only version had: the rows may be unchanged
    /// but the session still has to exist server-side before its photos can reference it,
    /// and an upsert of unchanged rows costs one request and changes nothing.
    func syncWorkout() {
        let session = activeSession

        Task { [store] in
            do {
                try await WorkoutSyncService.sync(session, store: store)
            } catch {
                // Not surfaced: the workout is already saved locally, and a failed sync is a
                // normal offline outcome rather than something the user must act on.
                print("Workout sync deferred: \(error)")
            }
        }
    }

    /// Leaves the workout without finishing it. The session stays `.active`, so the Workouts
    /// list keeps offering it under In Progress to resume — the same treatment a session the
    /// app was killed during gets. Pending edits are flushed on the way out so resuming
    /// shows the sets as they were left.
    func exitWorkout() {
        stopTimers()
        persist()
        // After the save, so the last thing published is what the user actually left behind.
        endLiveBroadcast()
    }

    /// Changes when the workout happened: its start, and its end once it has one.
    ///
    /// The clock is refreshed here rather than waiting on the next tick, so the header agrees
    /// with the sheet the moment it closes — in editing mode nothing ticks at all, so the
    /// duration would otherwise keep showing the old span until the screen was reopened.
    func rescheduleSession(startTime: Date, endTime: Date? = nil) {
        guard persist({ try store.reschedule(activeSession, startTime: startTime, endTime: endTime) }) else {
            return
        }
        elapsedTime = activeSession.duration
    }

    func renameSession(to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        activeSession.title = trimmed
        persist()
    }

    private func stopTimers() {
        sessionTimer?.invalidate()
        sessionTimer = nil
        restTimer?.invalidate()
        restTimer = nil
        liveBroadcastTimer?.invalidate()
        liveBroadcastTimer = nil
        isRestTimerRunning = false
    }

    // MARK: - Persistence plumbing

    /// Runs a store mutation, recording any failure for the UI. Returns whether it succeeded.
    @discardableResult
    private func persist(_ work: () throws -> Void = {}) -> Bool {
        do {
            try work()
            try store.save()
            return true
        } catch {
            persistenceErrorMessage = error.localizedDescription
            return false
        }
    }
}
