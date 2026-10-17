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
            }
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
        }
    }
}

#Preview {
    WorkoutsView()
}
