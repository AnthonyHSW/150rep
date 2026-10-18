import SwiftUI

enum SetField: Hashable {
    case weight(UUID)
    case reps(UUID)
}

struct SetRowView: View {
    @Bindable var set: ExerciseSet
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

    @AppStorage(PreferenceKey.weightUnit) private var weightUnit = WeightUnit.kilograms

    /// Exactly what the user has typed, held only while the field has focus.
    ///
    /// Deriving the field's text from the stored value alone can't represent a number
    /// mid-entry: "13." parses to 13 and renders back as "13", so the decimal point is eaten
    /// the moment it's typed and a fractional weight can't be entered at all. Keeping the raw
    /// string until focus leaves lets the user type freely, and the stored value still
    /// updates on every keystroke.
    @State private var weightDraft: String?

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

            TextField("0", text: weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: 60, height: Self.rowHeight)
                .background(set.isCompleted ? Color.green.opacity(0.25) : AppColors.pageBackground)
                .cornerRadius(8)
                .focused(focusedField, equals: .weight(set.id))

            TextField("0", text: repsText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 60, height: Self.rowHeight)
                .background(set.isCompleted ? Color.green.opacity(0.25) : AppColors.pageBackground)
                .cornerRadius(8)
                .focused(focusedField, equals: .reps(set.id))

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
