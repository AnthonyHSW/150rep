import Foundation
import SwiftData
import SwiftUI
import UIKit

@Observable
@MainActor
final class ActiveWorkoutViewModel: Identifiable {
    /// Held as a plain value rather than read off `activeSession`, so `Identifiable` is
    /// satisfied without the identity itself becoming main-actor isolated.
    nonisolated let id: UUID

    var activeSession: WorkoutSession
    var elapsedTime: TimeInterval = 0
    var restElapsed: Int = 0
    var restTargetDuration: Int = 90
    var isRestTimerRunning: Bool = false

    /// Set when a write to the store fails, so the UI can tell the user their work didn't
    /// save instead of silently carrying on.
    var persistenceErrorMessage: String?

    private let store: WorkoutStore
    private var sessionTimer: Timer?
    private var restTimer: Timer?
    private var hasNotifiedRestTarget = false

    init(session: WorkoutSession, store: WorkoutStore) {
        self.id = session.id
        self.activeSession = session
        self.store = store
        startSessionTimer()
    }

    func startSessionTimer() {
        elapsedTime = Date().timeIntervalSince(activeSession.startTime)
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.elapsedTime = Date().timeIntervalSince(self.activeSession.startTime)
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
            startRestTimer()
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
            // so they can retry Finish.
            startSessionTimer()
            return false
        }
        return true
    }

    /// Leaves the workout without finishing it. The session stays `.active`, so the Workouts
    /// list keeps offering it under In Progress to resume — the same treatment a session the
    /// app was killed during gets. Pending edits are flushed on the way out so resuming
    /// shows the sets as they were left.
    func exitWorkout() {
        stopTimers()
        persist()
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
