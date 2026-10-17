import SwiftUI

struct RestTimerDockView: View {
    let secondsRemaining: Int
    let onAddTime: () -> Void
    let onSkip: () -> Void

    private var formatted: String {
        let minutes = secondsRemaining / 60
        let seconds = secondsRemaining % 60
        return String(format: "%01d:%02d", minutes, seconds)
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rest")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(formatted)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
            }

            Spacer()

            Button(action: onAddTime) {
                Text("+10s")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)

            Button(action: onSkip) {
                Text("Skip")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.brandBlue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppColors.contentSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.horizontal, 16)
    }
}

#Preview {
    RestTimerDockView(secondsRemaining: 75, onAddTime: {}, onSkip: {})
}
