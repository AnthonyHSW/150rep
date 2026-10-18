import Foundation
import SwiftData

enum SetType: String, Codable, CaseIterable {
    case warmup = "W"
    case normal = "N"
    case dropSet = "D"
    case failure = "F"
}

@Model
final class ExerciseSet {
    @Attribute(.unique) var id: UUID
    var setNumber: Int
    var setTypeRaw: String
    var weight: Double
    var reps: Int
    var isCompleted: Bool
    var completedAt: Date?

    /// How long the set was held, for an exercise whose log is `isCardio`. Nil on every
    /// weight-and-reps set, and nil rather than zero on a time-based set nobody has filled in
    /// yet — "0:00" reads as a hold that happened and lasted no time.
    ///
    /// `weight` and `reps` stay non-optional and sit at zero for these sets; the sync layer is
    /// what turns them into the explicit nulls the server stores.
    var durationSeconds: Int?

    var exerciseLog: ExerciseLog?

    var setType: SetType {
        get { SetType(rawValue: setTypeRaw) ?? .normal }
        set { setTypeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        setNumber: Int,
        setType: SetType = .normal,
        weight: Double = 0.0,
        reps: Int = 0,
        durationSeconds: Int? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.setNumber = setNumber
        self.setTypeRaw = setType.rawValue
        self.weight = weight
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }
}
