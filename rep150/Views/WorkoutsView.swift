import SwiftUI

struct WorkoutsView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Button(action: {}) {
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

                Spacer()
            }
            .padding(16)
            .background(AppColors.pageBackground)
            .navigationTitle("Workouts")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
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
    }
}

#Preview {
    WorkoutsView()
}
