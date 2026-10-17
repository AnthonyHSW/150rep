import Foundation

/// A catalog entry (from `Exercises.csv`) that a user can add to an active workout.
/// Distinct from `ExerciseLog`, which is the logged instance of an exercise inside a session.
struct Exercise: Identifiable, Hashable {
    let id: String
    let name: String
    let primaryMuscle: String
}
