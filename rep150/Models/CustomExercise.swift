import Foundation
import SwiftData

/// An exercise the user added themselves, alongside the ones bundled in `Exercises.csv`.
///
/// Stored rather than written back into the CSV: the bundle is read-only on device, and a
/// catalog the user can edit is a different thing from the one that ships with the app. Kept
/// as its own model so the two can be told apart — the picker lets you delete yours and not
/// the built-in ones.
@Model
final class CustomExercise {
    /// Catalog id, matching `Exercise.id` — the key `ExerciseLog.exerciseId` stores and the
    /// PREVIOUS column looks up.
    ///
    /// A `custom-<uuid>` string rather than a slug of the name, for two reasons: it can't
    /// collide with a bundled id (or with another custom exercise of the same name), and it
    /// survives a rename, so history doesn't detach from an exercise that gets relabelled.
    @Attribute(.unique) var id: String
    var name: String
    var primaryMuscle: String
    var isCardio: Bool
    var createdAt: Date

    init(
        id: String = "custom-\(UUID().uuidString.lowercased())",
        name: String,
        primaryMuscle: String,
        isCardio: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.primaryMuscle = primaryMuscle
        self.isCardio = isCardio
        self.createdAt = createdAt
    }

    /// The catalog shape, so a custom exercise travels through the picker, the store, and the
    /// sync payload as any other exercise. No `imageName`: there is no artwork to name, and
    /// `ExerciseIconView` already falls back to its generic symbol for an empty one.
    var exercise: Exercise {
        Exercise(
            id: id,
            name: name,
            primaryMuscle: primaryMuscle,
            imageName: "",
            isCardio: isCardio
        )
    }
}
