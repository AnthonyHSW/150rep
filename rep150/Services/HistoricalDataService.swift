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
}
