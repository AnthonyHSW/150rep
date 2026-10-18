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

    /// Whether this exercise is measured in time rather than weight and reps.
    ///
    /// Lives on the log, not the set: a plank is time-based every time it is logged, and sets
    /// under one exercise must not disagree about which columns mean anything. Defaulted so
    /// adding it doesn't fail to open a store written before it existed.
    var isCardio: Bool = false

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
        isCardio: Bool = false,
        sets: [ExerciseSet] = []
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.name = name
        self.primaryMuscle = primaryMuscle
        self.imageName = imageName
        self.orderIndex = orderIndex
        self.notes = notes
        self.isCardio = isCardio
        self.sets = sets
    }

    /// Weight moved, in kilograms. Zero for a time-based exercise — a two-minute plank is
    /// work, but not work this number can describe, and inventing a figure for it would
    /// quietly inflate every total that sums volume.
    var totalVolume: Double {
        guard !isCardio else { return 0 }
        return sets.filter { $0.isCompleted }
            .reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
    }
}
