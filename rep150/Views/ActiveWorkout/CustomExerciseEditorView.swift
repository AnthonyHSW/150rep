import SwiftUI

/// Creates an exercise the bundled catalog doesn't have.
///
/// Asks for the three things the rest of the app needs from a catalog entry — a name, a muscle
/// group to file it under, and whether it is measured in time — and nothing else. Anything
/// further (artwork, equipment, notes) is a field the user would have to fill in before they
/// could get back to the workout they were in the middle of logging.
struct CustomExerciseEditorView: View {
    /// Groups already in use, offered so a new exercise lands in an existing section instead
    /// of creating "core" next to "Core".
    let existingMuscles: [String]
    let onSave: (_ name: String, _ muscle: String, _ isCardio: Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedMuscle: String
    @State private var newMuscle = ""
    @State private var isCardio = false

    /// Sentinel for the "new group" row in the picker. A tag no muscle can equal, so it can't
    /// be confused with a real selection.
    private static let newGroupTag = ""

    init(
        existingMuscles: [String],
        onSave: @escaping (_ name: String, _ muscle: String, _ isCardio: Bool) -> Void
    ) {
        self.existingMuscles = existingMuscles
        self.onSave = onSave
        _selectedMuscle = State(initialValue: existingMuscles.first ?? Self.newGroupTag)
    }

    private var isCreatingGroup: Bool { selectedMuscle == Self.newGroupTag }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The group this will be filed under, with the capitalisation the existing ones use.
    private var resolvedMuscle: String {
        guard isCreatingGroup else { return selectedMuscle }
        let trimmed = newMuscle.trimmingCharacters(in: .whitespacesAndNewlines)
        // Matched case-insensitively against what already exists, so typing "core" files the
        // exercise under the existing "Core" rather than starting a second section beside it.
        if let match = existingMuscles.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return match
        }
        return trimmed.capitalized
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !resolvedMuscle.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise name", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("Muscle Group") {
                    Picker("Group", selection: $selectedMuscle) {
                        ForEach(existingMuscles, id: \.self) { muscle in
                            Text(muscle).tag(muscle)
                        }
                        Text("New Group…").tag(Self.newGroupTag)
                    }

                    if isCreatingGroup {
                        TextField("Group name", text: $newMuscle)
                            .textInputAutocapitalization(.words)
                    }
                }

                Section {
                    Toggle("Measured in time", isOn: $isCardio)
                } footer: {
                    // Says what the toggle changes rather than what it is called, because the
                    // consequence is the part that decides the answer.
                    Text(isCardio
                         ? "Sets are logged in minutes and seconds, like a plank. They don't count toward volume."
                         : "Sets are logged in weight and reps.")
                }
            }
            .navigationTitle("New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmedName, resolvedMuscle, isCardio)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }
}

#Preview {
    CustomExerciseEditorView(existingMuscles: ["Arms", "Back", "Core"]) { _, _, _ in }
}
