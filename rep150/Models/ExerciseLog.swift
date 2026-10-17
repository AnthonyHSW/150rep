import Foundation
import SwiftData

@Model
final class ExerciseLog {
    @Attribute(.unique) var id: UUID
    var exerciseId: String
    var name: String
    var primaryMuscle: String
    var imageName: String = ""
    var orderIndex: Int
    var notes: String?

    @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.exerciseLog)
    var sets: [ExerciseSet]

    var workoutSession: WorkoutSession?

    init(
        id: UUID = UUID(),
        exerciseId: String,
        name: String,
        primaryMuscle: String,
        imageName: String = "",
        orderIndex: Int,
        notes: String? = nil,
        sets: [ExerciseSet] = []
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.name = name
        self.primaryMuscle = primaryMuscle
        self.imageName = imageName
        self.orderIndex = orderIndex
        self.notes = notes
        self.sets = sets
    }

    var totalVolume: Double {
        sets.filter { $0.isCompleted }
            .reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
    }
}
