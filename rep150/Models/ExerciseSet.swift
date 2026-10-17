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
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.setNumber = setNumber
        self.setTypeRaw = setType.rawValue
        self.weight = weight
        self.reps = reps
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }
}
