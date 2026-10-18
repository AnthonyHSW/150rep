import Foundation

/// A catalog entry (from `Exercises.csv`) that a user can add to an active workout.
/// Distinct from `ExerciseLog`, which is the logged instance of an exercise inside a session.
struct Exercise: Identifiable, Hashable {
    let id: String
    let name: String
    let primaryMuscle: String
    let imageName: String
    /// Measured by how long it was held rather than by weight and reps — a plank, not a
    /// bench press. Named for the `is_cardio` column it maps to server-side.
    let isCardio: Bool
}
