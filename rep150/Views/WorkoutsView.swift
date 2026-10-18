import SwiftUI
import SwiftData

struct WorkoutsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var activeViewModel: ActiveWorkoutViewModel?
    @State private var interruptedSession: WorkoutSession?
    @State private var errorMessage: String?

    /// Holds the "No active workouts" placeholder back while a swiped-away row animates out
    /// of the list, so the two don't crossfade over each other.
    @State private var isHoldingEmptyPlaceholder = false

    /// Other people's workouts happening right now.
    @State private var liveWorkouts: [LiveWorkout] = []
    /// Only true for the first load. A refresh keeps the rows that are already on screen
    /// rather than replacing them with a spinner, which would make the list flicker every
    /// time the poll comes round.
    @State private var isLoadingLiveWorkouts = true
    @State private var watchedWorkout: LiveWorkout?

    /// How often the feed is re-read while this screen is up. Shorter than the broadcast
    /// interval on the lifting side, so a set that gets published is picked up on roughly
    /// the next poll rather than a minute after it.
    private static let liveFeedRefreshInterval: TimeInterval = 30

    private var store: WorkoutStore {
        WorkoutStore(modelContext: modelContext)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: startWorkout) {
                        Text("Start Workout")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .background(AppColors.brandBlue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                Section {
                    if let interruptedSession {
                        inProgressRow(for: interruptedSession)
                    } else if !isHoldingEmptyPlaceholder {
                        Text("No active workouts")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("In Progress")
                }
                .listRowBackground(AppColors.contentSurface)

                Section {
                    if isLoadingLiveWorkouts {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Looking for workouts…")
                                .foregroundColor(.secondary)
                        }
                    } else if liveWorkouts.isEmpty {
                        Text("Nobody else is working out right now")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(liveWorkouts) { workout in
                            Button { watchedWorkout = workout } label: {
                                LiveWorkoutRow(workout: workout)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Active Workouts")
                } footer: {
                    // Shown whether or not anybody else is lifting: it is about what this
                    // user broadcasts, not about what the list happens to hold right now.
                    Text("Anyone at the Arc can see your workout while you have it open.")
                }
                .listRowBackground(AppColors.contentSurface)
            }
            .refreshable { await refreshLiveWorkouts() }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.pageBackground)
            .navigationTitle("Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    LogoView()
                        .frame(width: 70, height: 28)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Create Routine", action: {})
                        Button("Manage Routines", action: {})
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.headline)
                    }
                }
            }
            .task { loadInterruptedSession() }
            .task {
                // Polled rather than pushed: the rows it reads are written by other devices,
                // so nothing local changes when a workout starts or a set lands. Cancelled
                // with the screen, so it only runs while somebody is looking at it.
                while !Task.isCancelled {
                    await refreshLiveWorkouts()
                    do {
                        try await Task.sleep(for: .seconds(Self.liveFeedRefreshInterval))
                    } catch {
                        return
                    }
                }
            }
            .task(id: isHoldingEmptyPlaceholder) {
                guard isHoldingEmptyPlaceholder else { return }
                // Cancellation (the view going away, or the hold being lifted early) throws
                // out of the sleep — leave the flag alone and let whoever cancelled own it.
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                withAnimation(.easeIn(duration: 0.2)) {
                    isHoldingEmptyPlaceholder = false
                }
            }
            .alert("Something Went Wrong", isPresented: .constant(errorMessage != nil)) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .fullScreenCover(item: $activeViewModel, onDismiss: loadInterruptedSession) { viewModel in
            ActiveWorkoutView(viewModel: viewModel)
        }
        .sheet(item: $watchedWorkout) { workout in
            LiveWorkoutDetailView(workout: workout)
        }
    }

    /// The workout that's still open — either one in progress or one the app was killed
    /// during. Tapping resumes it; a leading swipe throws it away.
    private func inProgressRow(for session: WorkoutSession) -> some View {
        Button { resume(session) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Started \(session.startTime.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(AppColors.brandBlue)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(session)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// The workout still open, if any — one the user exited without finishing, or one the
    /// app was killed in the middle of. Runs at launch and again whenever the active-workout
    /// screen closes, so exiting puts the session back under In Progress to resume while
    /// finishing (which marks it `.completed`) drops it from the section.
    private func loadInterruptedSession() {
        do {
            interruptedSession = try store.interruptedSession()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Re-reads the live feed. A failure leaves whatever is already on screen alone: these
    /// rows are somebody else's workout and nothing here depends on them, so a dropped poll
    /// is better shown as slightly stale than as an empty list or an alert.
    private func refreshLiveWorkouts() async {
        defer { isLoadingLiveWorkouts = false }
        do {
            liveWorkouts = try await LiveWorkoutService.fetchLiveWorkouts()
        } catch {
            print("Failed to load live workouts: \(error)")
            return
        }

        // An open detail sheet holds a snapshot of a workout that is still changing, so the
        // poll has to carry through to it or a watcher sees the sets frozen at whatever they
        // were when they tapped. Matched by id; the last snapshot is kept when the workout
        // drops out of the feed, rather than yanking the sheet away mid-read.
        if let watched = watchedWorkout {
            watchedWorkout = liveWorkouts.first { $0.id == watched.id } ?? watched
        }
    }

    private func startWorkout() {
        do {
            let session = try store.startSession()
            activeViewModel = ActiveWorkoutViewModel(session: session, store: store)
            interruptedSession = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resume(_ session: WorkoutSession) {
        activeViewModel = ActiveWorkoutViewModel(session: session, store: store)
        interruptedSession = nil
    }

    private func delete(_ session: WorkoutSession) {
        // Clear the reference before deleting so nothing re-renders the row against a
        // deleted model object.
        interruptedSession = nil
        // The row is still swiping out of the list at this point; swapping the placeholder in
        // straight away would fade it up underneath the workout name on its way off screen.
        isHoldingEmptyPlaceholder = true
        do {
            try store.discard(session)
        } catch {
            errorMessage = error.localizedDescription
            isHoldingEmptyPlaceholder = false
            loadInterruptedSession()
            return
        }

        // `discard` only leaves a tombstone; the request itself goes out on the next sync,
        // which could be the next launch. For a workout that was being broadcast that is too
        // late — it would stay in everybody else's Active Workouts until the server's live
        // window aged it out. Flushing now takes it down with the swipe.
        let store = store
        Task {
            do {
                try await WorkoutSyncService.flushDeletions(store: store)
            } catch {
                // The tombstone survives, so the deletion still reaches the server later.
                print("Workout deletion deferred: \(error)")
            }
        }
    }
}

// MARK: - Live Workout Row

/// One watchable workout, collapsed to a single line: whose it is, what they called it, and
/// how far in they are.
private struct LiveWorkoutRow: View {
    let workout: LiveWorkout

    var body: some View {
        HStack(spacing: 12) {
            LiveWorkoutAvatar(workout: workout, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(workout.ownerDisplayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    LiveNowLabel()
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(workout.duration.workoutClockText)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
    }

    /// What they're on and how much they've done. Falls back to the workout's name while
    /// there is nothing logged yet, so a freshly started workout still says something.
    private var subtitle: String {
        let sets = workout.totalCompletedSets
        guard let exercise = workout.currentExerciseName else { return workout.title }
        return sets > 0
            ? "\(exercise) · \(sets) \(sets == 1 ? "set" : "sets")"
            : exercise
    }
}

#Preview {
    WorkoutsView()
}
