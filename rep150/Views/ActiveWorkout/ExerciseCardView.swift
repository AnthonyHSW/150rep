import SwiftUI

/// Section header for one exercise within the active workout `List`.
struct ExerciseCardHeaderView: View {
    let exercise: ExerciseLog
    let onRemoveExercise: () -> Void

    var body: some View {
        HStack {
            ExerciseIconView(imageName: exercise.imageName, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Text(exercise.primaryMuscle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Menu {
                Button("Remove Exercise", role: .destructive, action: onRemoveExercise)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
            }
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }
}

/// Column headings (`SET`, `PREVIOUS`, `KG`, `REPS`) shown above each exercise's set rows.
struct SetColumnHeaderView: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("SET").frame(width: 32, alignment: .center)
            Text("PREVIOUS").frame(width: 80, alignment: .leading)
            Text("KG").frame(width: 60, alignment: .center)
            Text("REPS").frame(width: 60, alignment: .center)
            Spacer().frame(width: 44)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.secondary)
        .padding(.horizontal, 4)
    }
}
