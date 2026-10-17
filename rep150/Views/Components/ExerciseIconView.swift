import SwiftUI
import UIKit

/// Shows an exercise's catalog icon, falling back to a generic SF Symbol
/// when the named asset hasn't been added to `Assets.xcassets` yet.
struct ExerciseIconView: View {
    let imageName: String
    var size: CGFloat = 36

    private var hasAsset: Bool {
        !imageName.isEmpty && UIImage(named: imageName) != nil
    }

    var body: some View {
        Group {
            if hasAsset {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.secondary)
                    .padding(size * 0.22)
                    .background(Color.secondary.opacity(0.1))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

#Preview {
    HStack {
        ExerciseIconView(imageName: "bench-press")
        ExerciseIconView(imageName: "does-not-exist")
    }
}
