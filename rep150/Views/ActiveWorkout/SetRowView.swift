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

    private var weightText: Binding<String> {
        Binding(
            get: { set.weight == 0 ? "" : formatted(set.weight) },
            set: { set.weight = Double($0) ?? 0 }
        )
    }

    private var repsText: Binding<String> {
        Binding(
            get: { set.reps == 0 ? "" : "\(set.reps)" },
            set: { set.reps = Int($0) ?? 0 }
        )
    }

    private static let rowHeight: CGFloat = 29

    var body: some View {
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
        .background(set.isCompleted ? Color.green.opacity(0.12) : Color.clear)
        .cornerRadius(8)
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(value)
    }
}
