import SwiftUI
import SwiftData
import UIKit

struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ActiveWorkoutViewModel

    @State private var isShowingExercisePicker = false
    @State private var isShowingFinishConfirm = false
    @State private var isRenamingSession = false
    @State private var sessionTitleDraft = ""
    @State private var isHeaderCondensed = false
    @FocusState private var focusedField: SetField?

    // Reorder state. `dragTranslationY` is the raw gesture translation; `dragSlotCompensation`
    // cancels out the layout shifts caused by live reordering and auto-scrolling, so the card
    // stays pinned under the finger no matter how many positions it has already travelled.
    @State private var expandedHeights: [UUID: CGFloat] = [:]
    @State private var draggingExerciseId: UUID?
    @State private var dragTranslationY: CGFloat = 0
    @State private var dragSlotCompensation: CGFloat = 0
    @State private var dragPointY: CGFloat = 0

    // Scrolling state.
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var scrollMetrics = ScrollMetrics()
    @State private var viewportFrame: CGRect = .zero
    @State private var autoScrollTimer: Timer?
    @State private var autoScrollRate: CGFloat = 0

    private let cardSpacing: CGFloat = 12
    private let autoScrollEdgeInset: CGFloat = 110
    private let autoScrollMaxStep: CGFloat = 16

    /// Every card is folded to the same height during a drag, so one constant describes
    /// the distance between any two neighbours.
    private var collapsedSpan: CGFloat {
        ExerciseCardView.collapsedHeight + cardSpacing
    }

    private var sortedExercises: [ExerciseLog] {
        viewModel.orderedExercises
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
                exerciseScrollView

                if viewModel.isRestTimerRunning && focusedField == nil {
                    RestTimerDockView(
                        secondsElapsed: viewModel.restElapsed,
                        targetSeconds: viewModel.restTargetDuration,
                        onSelectTarget: { viewModel.setRestTarget($0) },
                        onSkip: { viewModel.skipRest() }
                    )
                    .padding(.bottom, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // A finished workout has nothing to exit from — it's already saved, so
                    // the only way out is Done.
                    if viewModel.mode == .live {
                        Button("Exit") {
                            viewModel.exitWorkout()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Button {
                        sessionTitleDraft = viewModel.activeSession.title
                        isRenamingSession = true
                    } label: {
                        Text(viewModel.activeSession.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    switch viewModel.mode {
                    case .live:
                        Button("Finish") {
                            isShowingFinishConfirm = true
                        }
                        .fontWeight(.semibold)

                    case .editing:
                        // Edits are already written as they're made, so this just flushes and
                        // leaves — no confirmation to give.
                        Button("Done") {
                            viewModel.exitWorkout()
                            viewModel.syncWorkout()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
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
                            isShowingFinishConfirm = false
                            // Only leave the workout once it's actually stored; otherwise the
                            // alert explains why and the session stays put.
                            if viewModel.finishWorkout() {
                                viewModel.syncWorkout()
                                dismiss()
                            }
                        },
                        onCancel: { isShowingFinishConfirm = false }
                    )
                }
            }
            .animation(.easeOut(duration: 0.15), value: isShowingFinishConfirm)
            .alert("Rename Workout", isPresented: $isRenamingSession) {
                TextField("Workout name", text: $sessionTitleDraft)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    viewModel.renameSession(to: sessionTitleDraft)
                }
            }
            .alert(
                "Couldn't Save",
                isPresented: Binding(
                    get: { viewModel.persistenceErrorMessage != nil },
                    set: { if !$0 { viewModel.persistenceErrorMessage = nil } }
                ),
                presenting: viewModel.persistenceErrorMessage
            ) { _ in
                Button("OK", role: .cancel) { viewModel.persistenceErrorMessage = nil }
            } message: { message in
                Text(message)
            }
            .onDisappear(perform: stopAutoScroll)
        }
    }

    // MARK: - Scroll content

    private var exerciseScrollView: some View {
        ScrollView {
            // A plain `VStack` (not lazy) keeps every card measured, so the heights that
            // drive the index math are always available — including for the neighbour
            // just off-screen that a drag is about to cross.
            VStack(spacing: cardSpacing) {
                ForEach(sortedExercises) { exercise in
                    ExerciseCardView(
                        viewModel: viewModel,
                        exercise: exercise,
                        focusedField: $focusedField,
                        isCollapsed: draggingExerciseId != nil,
                        isDragging: draggingExerciseId == exercise.id,
                        onDragChanged: { handleDragChanged(exercise, value: $0) },
                        onDragEnded: { _ in handleDragEnded() }
                    )
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        // Only record full heights: during a drag every card reports the
                        // folded height, and the fold/unfold compensation needs to know
                        // how tall each card is when open.
                        if draggingExerciseId == nil {
                            expandedHeights[exercise.id] = height
                        }
                    }
                    .offset(y: draggingExerciseId == exercise.id ? dragVisualOffset : 0)
                    .zIndex(draggingExerciseId == exercise.id ? 1 : 0)
                }

                Button {
                    isShowingExercisePicker = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.brandBlue)
                .padding(.top, 4)

                WorkoutPhotoSectionView(session: viewModel.activeSession)
                    .padding(.top, 8)

                if viewModel.isRestTimerRunning {
                    Color.clear.frame(height: 72)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollPosition($scrollPosition)
        .scrollDismissesKeyboard(.interactively)
        // While reordering, scrolling is driven entirely by `autoScrollStep()`; letting the
        // scroll view pan at the same time would fight the drag.
        .scrollDisabled(draggingExerciseId != nil)
        .background(AppColors.pageBackground)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(
                offsetY: geometry.contentOffset.y,
                minOffsetY: -geometry.contentInsets.top,
                maxOffsetY: max(
                    -geometry.contentInsets.top,
                    geometry.contentSize.height - geometry.containerSize.height + geometry.contentInsets.bottom
                )
            )
        } action: { _, metrics in
            // Auto-scroll writes `scrollMetrics.offsetY` before asking for the scroll, so a
            // non-zero delta here during a drag means something else moved the content —
            // most often the scroll view clamping because folding made it shorter. Fold that
            // shift into the compensation too, or the card drifts away from the finger.
            if draggingExerciseId != nil {
                let externalDelta = metrics.offsetY - scrollMetrics.offsetY
                if abs(externalDelta) > 0.01 {
                    dragSlotCompensation += externalDelta
                }
            }

            scrollMetrics = metrics
            let condensed = metrics.scrolledDistance > 24
            if condensed != isHeaderCondensed {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHeaderCondensed = condensed
                }
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            viewportFrame = frame
        }
        .safeAreaInset(edge: .top) {
            WorkoutStatsHeaderView(
                elapsedLabel: elapsedLabel,
                totalVolumeLabel: totalVolumeLabel,
                completedSets: viewModel.activeSession.totalCompletedSets,
                isCondensed: isHeaderCondensed
            )
        }
    }

    // MARK: - Index-based reordering

    /// How far the dragged card sits from the slot the layout currently gives it.
    private var dragVisualOffset: CGFloat {
        dragTranslationY + dragSlotCompensation
    }

    private func handleDragChanged(_ exercise: ExerciseLog, value: DragGesture.Value) {
        if draggingExerciseId != exercise.id {
            focusedField = nil
            // Folding the list collapses every card above this one, lifting its slot by
            // the total shrink. Compensate up front so the card doesn't jump out from
            // under the finger as the list folds.
            dragSlotCompensation = foldDelta(above: exercise.id)
            draggingExerciseId = exercise.id
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
        dragTranslationY = value.translation.height
        dragPointY = value.location.y
        reconcileOrder(for: exercise.id)
        updateAutoScroll()
    }

    private func handleDragEnded() {
        stopAutoScroll()
        viewModel.commitExerciseOrder()

        // Unfolding grows every card above the dropped one, pushing it down the content.
        // Scrolling by the same amount leaves the card where the user released it.
        if let draggedId = draggingExerciseId {
            let growth = foldDelta(above: draggedId)
            if growth > 0 {
                // The content is about to get taller, so allow for the extra room the
                // current (still-folded) metrics don't know about yet.
                let headroom = foldDelta(above: nil)
                let target = min(max(scrollMetrics.offsetY + growth, scrollMetrics.minOffsetY),
                                 scrollMetrics.maxOffsetY + headroom)
                scrollMetrics.offsetY = target
                scrollPosition.scrollTo(y: target)
            }
        }

        withAnimation(.snappy) {
            draggingExerciseId = nil
            dragTranslationY = 0
            dragSlotCompensation = 0
        }
        dragPointY = 0
    }

    /// Total height the cards above `exerciseId` lose when folded (or the whole list's
    /// worth when `exerciseId` is nil).
    private func foldDelta(above exerciseId: UUID?) -> CGFloat {
        let ordered = sortedExercises
        let upperBound: Int
        if let exerciseId {
            guard let index = ordered.firstIndex(where: { $0.id == exerciseId }) else { return 0 }
            upperBound = index
        } else {
            upperBound = ordered.count
        }

        return ordered.prefix(upperBound).reduce(0) { total, exercise in
            let expanded = expandedHeights[exercise.id] ?? ExerciseCardView.collapsedHeight
            return total + max(0, expanded - ExerciseCardView.collapsedHeight)
        }
    }

    /// Walks the dragged card past each neighbour it has travelled more than halfway over,
    /// moving it one index at a time. Every card is folded during a drag, so one crossing is
    /// always `collapsedSpan` — which is also exactly how far the card's layout slot shifts,
    /// so the same amount comes back out of the visual offset to keep the card under the
    /// finger. The loop handles a single fast drag crossing several cards at once.
    private func reconcileOrder(for draggedId: UUID) {
        for _ in 0..<64 {
            let ordered = sortedExercises
            guard let currentIndex = ordered.firstIndex(where: { $0.id == draggedId }) else { return }
            let offset = dragVisualOffset

            if offset < -collapsedSpan / 2, currentIndex > 0 {
                viewModel.moveExercise(draggedId: draggedId, toIndex: currentIndex - 1, persist: false)
                dragSlotCompensation += collapsedSpan
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                continue
            }

            if offset > collapsedSpan / 2, currentIndex < ordered.count - 1 {
                viewModel.moveExercise(draggedId: draggedId, toIndex: currentIndex + 1, persist: false)
                dragSlotCompensation -= collapsedSpan
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                continue
            }

            return
        }
    }

    // MARK: - Auto-scroll while dragging

    private func updateAutoScroll() {
        guard draggingExerciseId != nil, viewportFrame.height > 0 else {
            stopAutoScroll()
            return
        }

        let topTrigger = viewportFrame.minY + autoScrollEdgeInset
        let bottomTrigger = viewportFrame.maxY - autoScrollEdgeInset

        if dragPointY < topTrigger {
            autoScrollRate = -min(1, (topTrigger - dragPointY) / autoScrollEdgeInset)
        } else if dragPointY > bottomTrigger {
            autoScrollRate = min(1, (dragPointY - bottomTrigger) / autoScrollEdgeInset)
        } else {
            stopAutoScroll()
            return
        }

        guard autoScrollTimer == nil else { return }
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            autoScrollStep()
        }
    }

    private func autoScrollStep() {
        guard let draggedId = draggingExerciseId else {
            stopAutoScroll()
            return
        }

        let target = min(max(scrollMetrics.offsetY + autoScrollRate * autoScrollMaxStep,
                             scrollMetrics.minOffsetY),
                         scrollMetrics.maxOffsetY)
        let applied = target - scrollMetrics.offsetY
        guard abs(applied) > 0.01 else {
            stopAutoScroll()
            return
        }

        scrollMetrics.offsetY = target
        scrollPosition.scrollTo(y: target)
        // Content slid by `applied`, taking the card's slot with it — hold the card still.
        dragSlotCompensation += applied
        reconcileOrder(for: draggedId)
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        autoScrollRate = 0
    }
}

/// Scroll offset plus the bounds it can be driven between, so auto-scroll never
/// pushes the content past either end.
private struct ScrollMetrics: Equatable {
    var offsetY: CGFloat = 0
    var minOffsetY: CGFloat = 0
    var maxOffsetY: CGFloat = 0

    /// Distance scrolled from rest, independent of the top safe-area inset.
    var scrolledDistance: CGFloat { offsetY - minOffsetY }
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
