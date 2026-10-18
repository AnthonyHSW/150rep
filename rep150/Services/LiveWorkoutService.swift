import Foundation
import Supabase

/// Reads the workouts other people have open right now.
///
/// Read-only by design: publishing is `WorkoutSyncService`'s job, and nothing here writes.
/// The server decides what is visible — the select policies added by `active_workouts.sql`
/// admit active sessions with a recent heartbeat and nothing else — so this cannot widen
/// what a user can see however it's called.
@MainActor
struct LiveWorkoutService {
    /// How long after its last heartbeat a workout stops counting as live.
    ///
    /// Mirrors `public.live_workout_cutoff()`. The server's copy is the one that enforces
    /// it; this one only keeps the app from asking for rows it already knows are stale —
    /// which matters because the owner policy still returns the *user's own* stale sessions
    /// regardless of this window.
    static let liveWindow: TimeInterval = 10 * 60

    /// Nested select, so one request returns each workout with its exercises and their sets.
    /// Walking the three tables separately would mean a request per workout per level, and
    /// the feed refreshes on a timer.
    private static let selectColumns = """
        id,user_id,title,start_time,last_active_at,owner_name,owner_avatar_url,\
        exercise_logs(id,name,primary_muscle,image_name,order_index,\
        exercise_sets(id,set_number,set_type,weight,reps,is_completed))
        """

    /// Every live workout except the signed-in user's own.
    ///
    /// Own workouts are excluded here rather than in the UI: the Workouts screen already
    /// shows the user's open session directly above this, under In Progress, where it can be
    /// resumed. Listing it a second time as something to watch would just be the same
    /// workout twice.
    static func fetchLiveWorkouts() async throws -> [LiveWorkout] {
        let userId = try await AuthService.currentUserId()
        let cutoff = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-liveWindow))

        let workouts: [LiveWorkout] = try await supabase
            .from(RemoteTable.workoutSessions.rawValue)
            .select(selectColumns)
            .eq("status", value: SessionStatus.active.rawValue)
            .gte("last_active_at", value: cutoff)
            .neq("user_id", value: userId.uuidString)
            .order("last_active_at", ascending: false)
            .execute()
            .value

        return workouts
    }
}
