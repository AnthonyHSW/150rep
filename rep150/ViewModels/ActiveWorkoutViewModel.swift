import Foundation
import SwiftData
import SwiftUI
import UIKit

@Observable
final class ActiveWorkoutViewModel {
    var activeSession: WorkoutSession
    var elapsedTime: TimeInterval = 0
    var restTimeRemaining: Int = 0
    var isRestTimerRunning: Bool = false

    private var sessionTimer: Timer?
    private var restTimer: Timer?
    private var modelContext: ModelContext

    init(session: WorkoutSession, modelContext: ModelContext) {
        self.activeSession = session
        self.modelContext = modelContext
        startSessionTimer()
    }

    func startSessionTimer() {
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.elapsedTime = Date().timeIntervalSince(self.activeSession.startTime)
        }
    }

    func toggleSetCompletion(_ set: ExerciseSet, defaultRestDuration: Int = 90) {
        set.isCompleted.toggle()
        set.completedAt = set.isCompleted ? Date() : nil

        try? modelContext.save()

        if set.isCompleted {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            startRestTimer(seconds: defaultRestDuration)
        }
    }

    func startRestTimer(seconds: Int) {
        restTimeRemaining = seconds
        isRestTimerRunning = true
        restTimer?.invalidate()

        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            if self.restTimeRemaining > 0 {
                self.restTimeRemaining -= 1
            } else {
                self.isRestTimerRunning = false
                timer.invalidate()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    func addRestTime(_ seconds: Int) {
        guard isRestTimerRunning else { return }
        restTimeRemaining += seconds
    }

    func skipRest() {
        restTimer?.invalidate()
        isRestTimerRunning = false
        restTimeRemaining = 0
    }

    func addExercise(_ exercise: Exercise) {
        let previousSets = HistoricalDataService.fetchPreviousSets(for: exercise.id, context: modelContext)
        let firstPrevious = previousSets.first

        let exerciseLog = ExerciseLog(
            exerciseId: exercise.id,
            name: exercise.name,
            primaryMuscle: exercise.primaryMuscle,
            imageName: exercise.imageName,
            orderIndex: activeSession.exercises.count
        )

        let initialSet = ExerciseSet(
            setNumber: 1,
            weight: firstPrevious?.weight ?? 0.0,
            reps: firstPrevious?.reps ?? 0
        )
        exerciseLog.sets.append(initialSet)

        exerciseLog.workoutSession = activeSession
        activeSession.exercises.append(exerciseLog)
        try? modelContext.save()
    }

    func removeExercise(_ exercise: ExerciseLog) {
        activeSession.exercises.removeAll { $0.id == exercise.id }
        modelContext.delete(exercise)
        try? modelContext.save()
    }

    func addSet(to exercise: ExerciseLog) {
        let newSetNumber = (exercise.sets.map { $0.setNumber }.max() ?? 0) + 1
        let lastSet = exercise.sets.last

        let newSet = ExerciseSet(
            setNumber: newSetNumber,
            setType: .normal,
            weight: lastSet?.weight ?? 0.0,
            reps: lastSet?.reps ?? 0
        )

        exercise.sets.append(newSet)
        try? modelContext.save()
    }

    func removeSet(_ set: ExerciseSet, from exercise: ExerciseLog) {
        exercise.sets.removeAll { $0.id == set.id }
        modelContext.delete(set)
        try? modelContext.save()
    }

    func previousSets(for exercise: ExerciseLog) -> [ExerciseSet] {
        HistoricalDataService.fetchPreviousSets(for: exercise.exerciseId, context: modelContext)
    }

    func finishWorkout() {
        sessionTimer?.invalidate()
        restTimer?.invalidate()
        activeSession.endTime = Date()
        activeSession.status = .completed
        try? modelContext.save()
    }

    func discardWorkout() {
        sessionTimer?.invalidate()
        restTimer?.invalidate()
        activeSession.status = .discarded
        modelContext.delete(activeSession)
        try? modelContext.save()
    }
}
