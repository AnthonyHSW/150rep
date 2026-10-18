import Foundation

/// Somebody else's workout, as it stands right now.
///
/// Deliberately not the `WorkoutSession` SwiftData model. These rows belong to other people
/// and are read-only: they are never saved to this device's store, never edited, and never
/// counted in this user's history. Decoding them into plain values keeps that impossible by
/// construction, rather than relying on every call site to remember it.
struct LiveWorkout: Identifiable, Decodable {
    let id: UUID
    let userId: UUID
    let title: String
    let startTime: Date
    /// When the owner's device last reported this workout open. The server only serves rows
    /// inside its live window, so this is recent by the time it arrives.
    let lastActiveAt: Date?
    /// The owner's Google name and picture as they were when the workout was published.
    /// Both optional — an account may have neither, which is why the avatar falls back to
    /// initials and the name falls back to `ownerDisplayName`.
    let ownerName: String?
    private let ownerAvatarUrl: String?
    let exercises: [LiveExercise]

    enum CodingKeys: String, CodingKey {
        case id, title
        case userId = "user_id"
        case startTime = "start_time"
        case lastActiveAt = "last_active_at"
        case ownerName = "owner_name"
        case ownerAvatarUrl = "owner_avatar_url"
        case exercises = "exercise_logs"
    }

    /// Parsed late rather than at decode time: a malformed URL in one row shouldn't fail the
    /// whole feed, and a missing picture is already an ordinary case here.
    var ownerAvatarURL: URL? {
        guard let ownerAvatarUrl, !ownerAvatarUrl.isEmpty else { return nil }
        return URL(string: ownerAvatarUrl)
    }

    /// Who to credit the workout to. Falls back to something neutral rather than the email
    /// address — the feed is the one place in the app where a name is shown to people other
    /// than its owner, and an address is more than they need.
    var ownerDisplayName: String {
        let trimmed = ownerName?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? "Someone at the Arc" : trimmed
    }

    /// Initials for the avatar fallback, on the same rules as `ProfileAvatarView`.
    var ownerInitials: String {
        let words = ownerDisplayName.split(separator: " ").prefix(2)
        return words.compactMap(\.first).map(String.init).joined().uppercased()
    }

    /// How long the workout has been going. Measured against now, like
    /// `WorkoutSession.duration` does for a session still running.
    var duration: TimeInterval { Date().timeIntervalSince(startTime) }

    var orderedExercises: [LiveExercise] {
        exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Volume of the work actually ticked off, matching `WorkoutSession.totalVolume` so the
    /// same number means the same thing whichever screen it's on.
    var totalVolume: Double {
        exercises.reduce(0.0) { $0 + $1.totalVolume }
    }

    var totalCompletedSets: Int {
        exercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count }
    }

    /// The exercise the owner is most likely on: the last one with a completed set, or the
    /// first on the list before anything has been ticked off. Shown on the collapsed row,
    /// where there's only space for one.
    var currentExerciseName: String? {
        let ordered = orderedExercises
        return ordered.last { $0.sets.contains(where: \.isCompleted) }?.name ?? ordered.first?.name
    }
}

/// One exercise inside a watched workout.
struct LiveExercise: Identifiable, Decodable {
    let id: UUID
    let name: String
    let primaryMuscle: String
    let imageName: String
    let orderIndex: Int
    let sets: [LiveSet]

    enum CodingKeys: String, CodingKey {
        case id, name
        case primaryMuscle = "primary_muscle"
        case imageName = "image_name"
        case orderIndex = "order_index"
        case sets = "exercise_sets"
    }

    var orderedSets: [LiveSet] {
        sets.sorted { $0.setNumber < $1.setNumber }
    }

    var totalVolume: Double {
        sets.filter(\.isCompleted)
            .reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
    }
}

/// One set inside a watched workout.
struct LiveSet: Identifiable, Decodable {
    let id: UUID
    let setNumber: Int
    private let setType: String
    /// Kilograms, as stored. Converted for display at the edge, the same as every other
    /// weight in the app.
    let weight: Double
    let reps: Int
    let isCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case id, weight, reps
        case setNumber = "set_number"
        case setType = "set_type"
        case isCompleted = "is_completed"
    }

    /// Unknown raw values fall back to a normal set rather than failing the decode: a build
    /// that learns a new set type shouldn't make its workouts unwatchable on older ones.
    var type: SetType { SetType(rawValue: setType) ?? .normal }
}
