import SwiftUI

struct RestTimerDockView: View {
    let secondsElapsed: Int
    let targetSeconds: Int
    let onSelectTarget: (Int) -> Void
    let onSkip: () -> Void

    private static let targetOptions = stride(from: 60, through: 300, by: 30).map { $0 }

    private var formatted: String {
        let minutes = secondsElapsed / 60
        let seconds = secondsElapsed % 60
        return String(format: "%01d:%02d", minutes, seconds)
    }

    private func label(for seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatted)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(secondsElapsed >= targetSeconds ? AppColors.brandBlue : .primary)
                }

                Spacer()

                Button(action: onSkip) {
                    Text("Skip")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.brandBlue)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.targetOptions, id: \.self) { seconds in
                        Button {
                            onSelectTarget(seconds)
                        } label: {
                            Text(label(for: seconds))
                                .font(.system(size: 13, weight: .semibold))
                                .monospacedDigit()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(seconds == targetSeconds ? AppColors.brandBlue : Color.secondary.opacity(0.12))
                                .foregroundColor(seconds == targetSeconds ? .white : .primary)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
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
    RestTimerDockView(secondsElapsed: 75, targetSeconds: 90, onSelectTarget: { _ in }, onSkip: {})
}
