import Foundation
import SwiftData

enum SessionStatus: String, Codable {
    case active
    case completed
    case discarded
}

@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var title: String
    var startTime: Date
    var endTime: Date?
    var statusRaw: String
    var notes: String?

    @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.workoutSession)
    var exercises: [ExerciseLog]

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var totalVolume: Double {
        exercises.reduce(0.0) { $0 + $1.totalVolume }
    }

    var totalCompletedSets: Int {
        exercises.reduce(0) { count, exercise in
            count + exercise.sets.filter { $0.isCompleted }.count
        }
    }

    init(
        id: UUID = UUID(),
        title: String = "Workout",
        startTime: Date = Date(),
        endTime: Date? = nil,
        status: SessionStatus = .active,
        notes: String? = nil,
        exercises: [ExerciseLog] = []
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.statusRaw = status.rawValue
        self.notes = notes
        self.exercises = exercises
    }
}

extension WorkoutSession {
    static func defaultTitle(for date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12: return "Morning Workout"
        case 12..<17: return "Afternoon Workout"
        case 17..<21: return "Evening Workout"
        default: return "Night Workout"
        }
    }
}
