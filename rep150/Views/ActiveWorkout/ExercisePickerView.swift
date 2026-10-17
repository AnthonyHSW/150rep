import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let onSelect: (Exercise) -> Void

    private var groups: [(muscle: String, exercises: [Exercise])] {
        let filtered = ExerciseCatalog.search(query)
        let grouped = Dictionary(grouping: filtered, by: \.primaryMuscle)
        return grouped.keys.sorted().map { muscle in
            (muscle: muscle, exercises: grouped[muscle]!.sorted { $0.name < $1.name })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.muscle) { group in
                    Section(group.muscle) {
                        ForEach(group.exercises) { exercise in
                            Button {
                                onSelect(exercise)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    ExerciseIconView(imageName: exercise.imageName, size: 32)
                                    Text(exercise.name)
                                        .foregroundColor(.primary)
                                }
                                .frame(minHeight: 35, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search exercises")
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if groups.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }
}

#Preview {
    ExercisePickerView(onSelect: { _ in })
}
