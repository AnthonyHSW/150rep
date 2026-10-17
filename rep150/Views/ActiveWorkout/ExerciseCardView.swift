import SwiftUI

/// One exercise rendered as a single self-contained card: drag handle, set column
/// headings, every set row, and the add-set button.
///
/// Encapsulating the whole exercise in one container is what makes index-based
/// reordering possible — the card is a single unit in the parent's `VStack`, so
/// moving an exercise is purely a matter of changing its index.
struct ExerciseCardView: View {
    /// Height of a folded card: the header's 52pt content plus the card's 12pt padding
    /// on each side. The frame below pins a collapsed card to exactly this, so the
    /// parent's reorder math can treat every folded card as the same known height
    /// instead of chasing measurements that are mid-animation.
    static let collapsedHeight: CGFloat = 76

    let viewModel: ActiveWorkoutViewModel
    let exercise: ExerciseLog
    var focusedField: FocusState<SetField?>.Binding
    var isCollapsed: Bool = false
    var isDragging: Bool = false
    var onDragChanged: (DragGesture.Value) -> Void = { _ in }
    var onDragEnded: (DragGesture.Value) -> Void = { _ in }

    private var sortedSets: [ExerciseSet] {
        exercise.sets.sorted { $0.setNumber < $1.setNumber }
    }

    var body: some View {
        VStack(spacing: 8) {
            ExerciseCardHeaderView(
                exercise: exercise,
                setCount: exercise.sets.count,
                isCollapsed: isCollapsed,
                onRemoveExercise: { viewModel.removeExercise(exercise) },
                isDragging: isDragging,
                onDragChanged: onDragChanged,
                onDragEnded: onDragEnded
            )

            if !isCollapsed {
                SetColumnHeaderView()

                ForEach(sortedSets) { set in
                    SetRowView(
                        set: set,
                        previousLabel: previousLabel(forSetNumber: set.setNumber),
                        focusedField: focusedField,
                        onToggleComplete: { viewModel.toggleSetCompletion(set) },
                        onCycleType: { cycleType(of: set) },
                        onDelete: { viewModel.removeSet(set, from: exercise) }
                    )
                }

                Button {
                    viewModel.addSet(to: exercise)
                } label: {
                    Label("Add Set", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 31)
                }
                .buttonStyle(.bordered)
                .tint(AppColors.brandBlue)
            }
        }
        .padding(12)
        .frame(height: isCollapsed ? Self.collapsedHeight : nil, alignment: .top)
        .background(AppColors.contentSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(isDragging ? 0.22 : 0), radius: isDragging ? 14 : 0, y: isDragging ? 6 : 0)
        .scaleEffect(isDragging ? 1.02 : 1)
    }

    private func previousLabel(forSetNumber setNumber: Int) -> String? {
        let previousSets = viewModel.previousSets(for: exercise)
        guard let previous = previousSets.first(where: { $0.setNumber == setNumber }) ?? previousSets.last else {
            return nil
        }
        let weightText = previous.weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(previous.weight))
            : String(previous.weight)
        return "\(weightText) kg × \(previous.reps)"
    }

    private func cycleType(of set: ExerciseSet) {
        let all = SetType.allCases
        let currentIndex = all.firstIndex(of: set.setType) ?? 0
        set.setType = all[(currentIndex + 1) % all.count]
    }
}

/// Title row for one exercise card, carrying the reorder grip.
struct ExerciseCardHeaderView: View {
    let exercise: ExerciseLog
    var setCount: Int = 0
    var isCollapsed: Bool = false
    let onRemoveExercise: () -> Void
    var isDragging: Bool = false
    var onDragChanged: (DragGesture.Value) -> Void = { _ in }
    var onDragEnded: (DragGesture.Value) -> Void = { _ in }

    /// With the set rows folded away, the subtitle carries the set count instead.
    private var subtitle: String {
        guard isCollapsed else { return exercise.primaryMuscle }
        let setLabel = setCount == 1 ? "1 set" : "\(setCount) sets"
        return "\(setLabel) · \(exercise.primaryMuscle)"
    }

    var body: some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(isDragging ? AppColors.brandBlue : .secondary)
                .frame(width: 52 * 0.8, height: 52 * 0.8)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .global)
                        .onChanged(onDragChanged)
                        .onEnded(onDragEnded)
                )

            ExerciseIconView(imageName: exercise.imageName, size: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
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
