import Foundation
import SwiftData

enum SessionStatus: String, Codable {
    case active
    case completed
    case discarded
}

@Model
final class WorkoutSession {
    /// Hard cap on photos per session. Kept here so the limit has one definition rather than
    /// being repeated across the picker, the counter, and the add guard.
    static let maxPhotoCount = 5

    @Attribute(.unique) var id: UUID
    var title: String
    var startTime: Date
    var endTime: Date?
    var statusRaw: String
    var notes: String?

    @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.workoutSession)
    var exercises: [ExerciseLog]

    /// Cascades the metadata rows only — the JPEGs they point at live on disk, so deleting a
    /// session or a photo has to clear those separately (see `WorkoutStore`).
    @Relationship(deleteRule: .cascade, inverse: \WorkoutPhoto.workoutSession)
    var photos: [WorkoutPhoto] = []

    /// When this session last reached Supabase, or `nil` if it never has.
    ///
    /// Optional for two reasons: a non-optional addition without a default would fail to open
    /// the existing store, and "never synced" has to be representable — it's what decides
    /// whether deleting a row needs a tombstone at all.
    var syncedAt: Date?

    /// Whether the server has never seen this session. Drives the catch-up sweep at launch;
    /// finishing a workout syncs it outright rather than consulting this, since the upserts
    /// are keyed on ids the device already owns and so cost nothing to repeat.
    var needsSync: Bool { syncedAt == nil }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var totalVolume: Double {
        exercises.reduce(0.0) { $0 + $1.totalVolume }
    }

    /// Elapsed time of the session; measured against now while it's still running.
    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }

    var totalCompletedSets: Int {
        exercises.reduce(0) { count, exercise in
            count + exercise.sets.filter { $0.isCompleted }.count
        }
    }

    /// Photos in the order they were added.
    var orderedPhotos: [WorkoutPhoto] {
        photos.sorted { $0.orderIndex < $1.orderIndex }
    }

    var canAddPhoto: Bool { photos.count < Self.maxPhotoCount }

    /// How many more photos this session will accept — also the cap handed to the picker.
    var remainingPhotoSlots: Int { max(0, Self.maxPhotoCount - photos.count) }

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

extension TimeInterval {
    /// A workout's elapsed time as a clock: `h:mm:ss` once it passes an hour, `mm:ss`
    /// before that.
    ///
    /// Spelled once because two screens show the same clock — the owner's active workout
    /// and a watcher's view of somebody else's — and a workout that reads 1:05:32 on one
    /// and 65:32 on the other is the same workout described two ways.
    var workoutClockText: String {
        let total = Int(max(0, self))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}
