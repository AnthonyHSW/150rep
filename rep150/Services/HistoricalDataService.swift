import SwiftData
import Foundation

struct HistoricalDataService {
    /// Returns the completed sets from the most recent completed session that logged this exercise,
    /// used to populate the `PREVIOUS` column and to default new set values.
    static func fetchPreviousSets(for exerciseId: String, context: ModelContext) -> [ExerciseSet] {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.statusRaw == "completed" },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )

        guard let completedSessions = try? context.fetch(descriptor) else { return [] }

        for session in completedSessions {
            if let matchingExercise = session.exercises.first(where: { $0.exerciseId == exerciseId }) {
                let completed = matchingExercise.sets
                    .filter { $0.isCompleted }
                    .sorted { $0.setNumber < $1.setNumber }
                if !completed.isEmpty {
                    return completed
                }
            }
        }

        return []
    }

    /// When each exercise was last logged, keyed by catalog id (`Exercise.id`), for ordering
    /// the picker by recency.
    ///
    /// Dated by the session's start rather than the set's `completedAt`: a session is the unit
    /// the user thinks in ("last Tuesday's workout"), and set timestamps are missing on
    /// anything logged before they were recorded.
    ///
    /// Completed sessions only, matching `fetchPreviousSets`. An exercise in the workout
    /// currently open is already on screen behind the picker, so counting it would spend the
    /// top of the list on exercises the user just added.
    static func lastLoggedDates(context: ModelContext) -> [String: Date] {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.statusRaw == "completed" },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )

        guard let completedSessions = try? context.fetch(descriptor) else { return [:] }

        var dates: [String: Date] = [:]
        // Newest first, so the first time an exercise is seen is its most recent outing.
        for session in completedSessions {
            for exercise in session.exercises where dates[exercise.exerciseId] == nil {
                dates[exercise.exerciseId] = session.startTime
            }
        }
        return dates
    }
}
