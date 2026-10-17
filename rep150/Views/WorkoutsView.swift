import SwiftUI
import SwiftData

struct WorkoutsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var activeViewModel: ActiveWorkoutViewModel?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 0)

                Button(action: startWorkout) {
                    Text("Start Workout")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(AppColors.brandBlue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Text("No active workouts")
                    .foregroundColor(.secondary)

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxHeight: .infinity)
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
        }
        .fullScreenCover(item: $activeViewModel) { viewModel in
            ActiveWorkoutView(viewModel: viewModel)
        }
    }

    private func startWorkout() {
        let session = WorkoutSession(title: WorkoutSession.defaultTitle())
        modelContext.insert(session)
        activeViewModel = ActiveWorkoutViewModel(session: session, modelContext: modelContext)
    }
}

extension ActiveWorkoutViewModel: Identifiable {
    var id: UUID { activeSession.id }
}

#Preview {
    WorkoutsView()
}
