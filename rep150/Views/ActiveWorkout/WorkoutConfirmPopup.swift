import SwiftUI

/// A centered popup notification, used in place of the system confirmation
/// dialog/alert chrome for the Discard/Finish prompts on the active workout page.
struct WorkoutConfirmPopup: View {
    let title: String
    let message: String?
    let confirmLabel: String
    let isDestructive: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                if let message {
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)

                    Button(action: onConfirm) {
                        Text(confirmLabel)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isDestructive ? .red : AppColors.brandBlue)
                }
                .padding(.top, 6)
            }
            .padding(20)
            .frame(width: 300)
            .background(AppColors.contentSurface)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
        }
        .transition(.opacity.combined(with: .scale(scale: 1.05)))
    }
}

#Preview {
    ZStack {
        AppColors.pageBackground.ignoresSafeArea()
        WorkoutConfirmPopup(
            title: "Discard this workout?",
            message: "This will delete all logged sets for this session.",
            confirmLabel: "Discard Workout",
            isDestructive: true,
            onConfirm: {},
            onCancel: {}
        )
    }
}
