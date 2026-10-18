import SwiftUI
import SwiftData

/// Picks a catalog exercise to add to the workout, ordered by when it was last logged.
///
/// Recency rather than muscle groups: the catalog is a fixed list the user works through a
/// handful of entries at a time, so what they reach for next is nearly always something they
/// did recently. Alphabetical muscle sections put Arms first every time and buried a regular
/// movement under a group heading; the muscle now rides along as a subtitle so nothing that
/// grouping conveyed is lost.
struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Exercises the user added, merged into the catalog below. Ordered by name so the
    /// unlogged section reads alphabetically whichever catalog an entry came from.
    @Query(sort: \CustomExercise.name) private var customExercises: [CustomExercise]

    @State private var query = ""
    @State private var isCreatingExercise = false
    /// Last-logged date per catalog id, loaded once when the sheet opens. Fetched into state
    /// rather than computed in `body`, which would re-read the whole session history on every
    /// keystroke in the search field.
    @State private var lastLogged: [String: Date] = [:]

    let onSelect: (Exercise) -> Void

    /// Exercises the user has logged before, most recent first.
    private var recent: [Exercise] {
        let logged: [(exercise: Exercise, date: Date)] = matches.compactMap { exercise in
            guard let date = lastLogged[exercise.id] else { return nil }
            return (exercise: exercise, date: date)
        }

        // Same-session ties fall back to the name, so the order is stable rather than
        // whatever the dictionary happened to yield.
        let ordered = logged.sorted { lhs, rhs in
            lhs.date == rhs.date ? lhs.exercise.name < rhs.exercise.name : lhs.date > rhs.date
        }

        return ordered.map(\.exercise)
    }

    /// Everything never logged, alphabetical — there is no recency to order it by.
    private var unlogged: [Exercise] {
        matches
            .filter { lastLogged[$0.id] == nil }
            .sorted { $0.name < $1.name }
    }

    /// The bundled catalog plus the user's own, filtered by the search field.
    ///
    /// Custom entries are matched here rather than inside `ExerciseCatalog`, which only knows
    /// about the CSV — the store is the view's to read, and the catalog has no model context.
    private var matches: [Exercise] {
        let custom = customExercises.map(\.exercise)
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return ExerciseCatalog.all + custom }

        return ExerciseCatalog.search(query)
            + custom.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Muscle groups already in use, for the new-exercise sheet to offer.
    private var knownMuscles: [String] {
        let all = ExerciseCatalog.all.map(\.primaryMuscle) + customExercises.map(\.primaryMuscle)
        return Array(Set(all)).sorted()
    }

    /// Ids of the user's own exercises, so only those offer a delete. A bundled exercise
    /// isn't the user's to remove — it would come back on the next launch regardless.
    private var customIds: Set<String> { Set(customExercises.map(\.id)) }

    var body: some View {
        NavigationStack {
            List {
                if !recent.isEmpty {
                    Section("Recent") {
                        ForEach(recent) { exercise in
                            row(for: exercise)
                        }
                        .onDelete { delete(at: $0, from: recent) }
                    }
                }

                if !unlogged.isEmpty {
                    // Only called "All Exercises" when it is the whole list; otherwise the
                    // recent section has already taken part of the catalog.
                    Section(recent.isEmpty ? "All Exercises" : "Not Logged Yet") {
                        ForEach(unlogged) { exercise in
                            row(for: exercise)
                        }
                        .onDelete { delete(at: $0, from: unlogged) }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search exercises")
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isCreatingExercise = true
                    } label: {
                        // An icon, not a Label: a toolbar Label renders its title alongside
                        // the glyph here, and "New Exercise" crowds the title out of a bar
                        // that already carries Cancel.
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Exercise")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $isCreatingExercise) {
                CustomExerciseEditorView(existingMuscles: knownMuscles) { name, muscle, isCardio in
                    createExercise(name: name, muscle: muscle, isCardio: isCardio)
                }
            }
            .overlay {
                if recent.isEmpty && unlogged.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .task {
                lastLogged = HistoricalDataService.lastLoggedDates(context: modelContext)
            }
        }
    }

    private func createExercise(name: String, muscle: String, isCardio: Bool) {
        modelContext.insert(
            CustomExercise(name: name, primaryMuscle: muscle, isCardio: isCardio)
        )
        // Saved immediately rather than left to the next autosave: the user is about to add
        // this exercise to a workout, and a context that never flushed would lose the
        // definition behind the sets that reference it.
        try? modelContext.save()
    }

    /// Deletes the user's own exercises at `offsets` within `list`.
    ///
    /// Bundled entries in the same section are skipped rather than refused outright, so a
    /// swipe on one simply does nothing. Workouts that already logged a deleted exercise keep
    /// it: `ExerciseLog` stores its own copy of the name and muscle, so history reads the
    /// same afterwards.
    private func delete(at offsets: IndexSet, from list: [Exercise]) {
        let ids = offsets.map { list[$0].id }.filter { customIds.contains($0) }
        guard !ids.isEmpty else { return }

        for custom in customExercises where ids.contains(custom.id) {
            modelContext.delete(custom)
        }
        try? modelContext.save()
    }

    private func row(for exercise: Exercise) -> some View {
        Button {
            onSelect(exercise)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ExerciseIconView(imageName: exercise.imageName, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .foregroundColor(.primary)
                    Text(subtitle(for: exercise))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(minHeight: 60, alignment: .leading)
        }
    }

    /// The muscle, plus how long ago this exercise was last logged — so the list's order is
    /// self-explaining rather than looking arbitrary.
    private func subtitle(for exercise: Exercise) -> String {
        guard let date = lastLogged[exercise.id] else { return exercise.primaryMuscle }
        let relative = Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
        return "\(exercise.primaryMuscle) · \(relative)"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

#Preview {
    ExercisePickerView(onSelect: { _ in })
}
