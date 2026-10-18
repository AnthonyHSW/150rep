import SwiftUI

enum SetField: Hashable {
    case weight(UUID)
    case reps(UUID)
    case minutes(UUID)
    case seconds(UUID)
}

struct SetRowView: View {
    @Bindable var set: ExerciseSet
    /// Swaps the two entry fields from weight and reps to minutes and seconds. Passed down
    /// from the exercise rather than read off the set, since it is the exercise that decides
    /// what its sets measure.
    var isCardio: Bool = false
    let previousLabel: String?
    var focusedField: FocusState<SetField?>.Binding
    let onToggleComplete: () -> Void
    let onCycleType: () -> Void
    let onDelete: () -> Void

    /// How far the row has to travel before letting go deletes the set.
    private static let deleteThreshold: CGFloat = 88
    private static let rowHeight: CGFloat = 29

    /// Live horizontal travel of the row under the finger. Rightwards only — the row
    /// slides aside to uncover the delete backdrop sitting behind it.
    @State private var dragOffset: CGFloat = 0

    @AppStorage(PreferenceKey.weightUnit) private var weightUnit = WeightUnit.default

    /// Exactly what the user has typed, held only while the field has focus.
    ///
    /// Deriving the field's text from the stored value alone can't represent a number
    /// mid-entry: "13." parses to 13 and renders back as "13", so the decimal point is eaten
    /// the moment it's typed and a fractional weight can't be entered at all. Keeping the raw
    /// string until focus leaves lets the user type freely, and the stored value still
    /// updates on every keystroke.
    @State private var weightDraft: String?

    /// The same treatment for the time fields, for a sharper reason: minutes and seconds are
    /// two views of one stored number, so typing "90" into seconds would re-split to 1:30 and
    /// rewrite the field to "30" under the user's finger. Holding the raw text until focus
    /// leaves lets them type, and normalizing on commit is what turns 90 into 1:30.
    @State private var minutesDraft: String?
    @State private var secondsDraft: String?

    private var weightText: Binding<String> {
        Binding(
            get: {
                if let weightDraft { return weightDraft }
                return set.weight == 0 ? "" : weightUnit.displayText(fromKilograms: set.weight)
            },
            set: { typed in
                weightDraft = typed
                // Stored in kilograms whatever is on screen, so history stays in one unit.
                set.weight = weightUnit.toKilograms(Double(typed) ?? 0)
            }
        )
    }

    private var repsText: Binding<String> {
        Binding(
            get: { set.reps == 0 ? "" : "\(set.reps)" },
            set: { set.reps = Int($0) ?? 0 }
        )
    }

    // MARK: - Time entry

    private var storedMinutes: Int { (set.durationSeconds ?? 0) / 60 }
    private var storedSeconds: Int { (set.durationSeconds ?? 0) % 60 }

    private var minutesText: Binding<String> {
        Binding(
            get: {
                if let minutesDraft { return minutesDraft }
                return storedMinutes == 0 ? "" : "\(storedMinutes)"
            },
            set: { typed in
                minutesDraft = typed
                commitDuration()
            }
        )
    }

    private var secondsText: Binding<String> {
        Binding(
            get: {
                if let secondsDraft { return secondsDraft }
                return storedSeconds == 0 ? "" : "\(storedSeconds)"
            },
            set: { typed in
                secondsDraft = typed
                commitDuration()
            }
        )
    }

    /// Folds whatever is in the two fields back into one duration.
    ///
    /// A cleared field reads as zero, not as "keep what was stored" — an empty draft is the
    /// user deleting the value, and falling back to the stored number would make it
    /// un-erasable. Both at zero stores nil rather than 0, so an untouched set stays blank
    /// instead of claiming a hold of no length.
    private func commitDuration() {
        let minutes = minutesDraft.map { Int($0) ?? 0 } ?? storedMinutes
        let seconds = secondsDraft.map { Int($0) ?? 0 } ?? storedSeconds
        let total = minutes * 60 + seconds
        set.durationSeconds = total > 0 ? total : nil
    }

    /// 0 at rest, 1 once the swipe is far enough to commit — drives how emphatic the
    /// backdrop looks, so the row reads as armed before the finger lifts.
    private var swipeProgress: CGFloat {
        min(1, dragOffset / Self.deleteThreshold)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            deleteBackdrop
            rowContent
                .offset(x: dragOffset)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .gesture(swipeGesture)
        .onChange(of: focusedField.wrappedValue) { _, field in
            // Focus gone: drop the raw text so the field falls back to the stored value,
            // rounded and in whatever unit is now selected.
            if field != .weight(set.id) { weightDraft = nil }
            if field != .minutes(set.id) { minutesDraft = nil }
            if field != .seconds(set.id) { secondsDraft = nil }
        }
        .contextMenu {
            Button("Delete Set", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            Button(action: onCycleType) {
                Text(set.setType == .normal ? "\(set.setNumber)" : set.setType.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: Self.rowHeight)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Text(previousLabel ?? "—")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 80, height: Self.rowHeight, alignment: .leading)
                .lineLimit(1)

            if isCardio {
                entryField(text: minutesText, keyboard: .numberPad, field: .minutes(set.id))
                entryField(text: secondsText, keyboard: .numberPad, field: .seconds(set.id))
            } else {
                entryField(text: weightText, keyboard: .decimalPad, field: .weight(set.id))
                entryField(text: repsText, keyboard: .numberPad, field: .reps(set.id))
            }

            Button(action: onToggleComplete) {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 20))
                    .foregroundColor(set.isCompleted ? .green : .secondary)
                    .frame(width: 44, height: Self.rowHeight)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .background(set.isCompleted ? Color.green.opacity(0.12) : AppColors.contentSurface)
        .cornerRadius(8)
    }

    /// The two entry boxes are identical but for their binding, keyboard, and focus tag —
    /// spelled once so the weight pair and the time pair can't drift apart visually.
    private func entryField(
        text: Binding<String>,
        keyboard: UIKeyboardType,
        field: SetField
    ) -> some View {
        TextField("0", text: text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .frame(width: 60, height: Self.rowHeight)
            .background(set.isCompleted ? Color.green.opacity(0.25) : AppColors.pageBackground)
            .cornerRadius(8)
            .focused(focusedField, equals: field)
    }

    /// Revealed as the row slides right; the icon only shows once there's room for it.
    private var deleteBackdrop: some View {
        HStack {
            Image(systemName: "trash.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .padding(.leading, 14)
                .opacity(Double(swipeProgress))
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
        .background(Color.red.opacity(0.55 + 0.45 * Double(swipeProgress)))
        .opacity(dragOffset > 0 ? 1 : 0)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                // Leave vertical drags to the scroll view, and ignore leftward travel —
                // only a rightward swipe means delete.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let travel = max(0, value.translation.width)
                // Past the threshold the row stiffens, so the commit point is felt.
                dragOffset = travel <= Self.deleteThreshold
                    ? travel
                    : Self.deleteThreshold + (travel - Self.deleteThreshold) * 0.35
            }
            .onEnded { _ in
                guard dragOffset >= Self.deleteThreshold else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffset = 0 }
                    return
                }
                // Let the row clear the screen before the model drops it, so the
                // deletion looks like the swipe finishing rather than a sudden gap.
                withAnimation(.easeOut(duration: 0.18)) { dragOffset = 500 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    onDelete()
                }
            }
    }
}
