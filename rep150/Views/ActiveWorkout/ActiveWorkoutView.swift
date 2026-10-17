import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ActiveWorkoutViewModel

    @State private var isShowingExercisePicker = false
    @State private var isShowingFinishConfirm = false
    @State private var isShowingDiscardConfirm = false
    @State private var isHeaderCondensed = false
    @FocusState private var focusedField: SetField?

    private var sortedExercises: [ExerciseLog] {
        viewModel.activeSession.exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    private var elapsedLabel: String {
        let total = Int(viewModel.elapsedTime)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    private var totalVolumeLabel: String {
        let volume = viewModel.activeSession.totalVolume
        return volume.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(volume)) kg"
            : String(format: "%.1f kg", volume)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                List {
                    ForEach(sortedExercises) { exercise in
                        Section {
                            SetColumnHeaderView()
                            ForEach(exercise.sets.sorted(by: { $0.setNumber < $1.setNumber })) { set in
                                SetRowView(
                                    set: set,
                                    previousLabel: previousLabel(for: exercise, setNumber: set.setNumber),
                                    focusedField: $focusedField,
                                    onToggleComplete: { viewModel.toggleSetCompletion(set) },
                                    onCycleType: { cycleType(of: set) }
                                )
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        viewModel.removeSet(set, from: exercise)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
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
                        } header: {
                            ExerciseCardHeaderView(exercise: exercise) {
                                viewModel.removeExercise(exercise)
                            }
                        }
                        .listRowBackground(AppColors.contentSurface)
                    }

                    Section {
                        Button {
                            isShowingExercisePicker = true
                        } label: {
                            Label("Add Exercise", systemImage: "plus.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 31)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.brandBlue)
                    }
                    .listRowBackground(Color.clear)

                    if viewModel.isRestTimerRunning {
                        Color.clear.frame(height: 72).listRowBackground(Color.clear)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(AppColors.pageBackground)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y > 24
                } action: { _, condensed in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHeaderCondensed = condensed
                    }
                }
                .safeAreaInset(edge: .top) {
                    WorkoutStatsHeaderView(
                        elapsedLabel: elapsedLabel,
                        totalVolumeLabel: totalVolumeLabel,
                        completedSets: viewModel.activeSession.totalCompletedSets,
                        isCondensed: isHeaderCondensed
                    )
                }

                if viewModel.isRestTimerRunning && focusedField == nil {
                    RestTimerDockView(
                        secondsRemaining: viewModel.restTimeRemaining,
                        onAddTime: { viewModel.addRestTime(10) },
                        onSkip: { viewModel.skipRest() }
                    )
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle(viewModel.activeSession.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Discard", role: .destructive) {
                        isShowingDiscardConfirm = true
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Finish") {
                        isShowingFinishConfirm = true
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $isShowingExercisePicker) {
                ExercisePickerView { exercise in
                    viewModel.addExercise(exercise)
                }
            }
            .overlay {
                if isShowingFinishConfirm {
                    WorkoutConfirmPopup(
                        title: "Finish this workout?",
                        message: nil,
                        confirmLabel: "Finish",
                        isDestructive: false,
                        onConfirm: {
                            viewModel.finishWorkout()
                            isShowingFinishConfirm = false
                            dismiss()
                        },
                        onCancel: { isShowingFinishConfirm = false }
                    )
                } else if isShowingDiscardConfirm {
                    WorkoutConfirmPopup(
                        title: "Discard this workout?",
                        message: "This will delete this session.",
                        confirmLabel: "Discard",
                        isDestructive: true,
                        onConfirm: {
                            viewModel.discardWorkout()
                            isShowingDiscardConfirm = false
                            dismiss()
                        },
                        onCancel: { isShowingDiscardConfirm = false }
                    )
                }
            }
            .animation(.easeOut(duration: 0.15), value: isShowingFinishConfirm)
            .animation(.easeOut(duration: 0.15), value: isShowingDiscardConfirm)
        }
    }

    private func previousLabel(for exercise: ExerciseLog, setNumber: Int) -> String? {
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

/// Pinned stats bar above the set list. Condenses into a single line once the user scrolls.
private struct WorkoutStatsHeaderView: View {
    let elapsedLabel: String
    let totalVolumeLabel: String
    let completedSets: Int
    let isCondensed: Bool

    var body: some View {
        Group {
            if isCondensed {
                HStack(spacing: 6) {
                    Text(elapsedLabel)
                    Text("·")
                    Text(totalVolumeLabel)
                    Text("·")
                    Text("\(completedSets) sets")
                }
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Duration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(elapsedLabel)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Volume · Sets")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(totalVolumeLabel) · \(completedSets)")
                            .font(.system(size: 16, weight: .semibold))
                            .monospacedDigit()
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.contentSurface)
    }
}
