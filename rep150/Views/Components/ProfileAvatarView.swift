import SwiftUI

/// Shows the signed-in account's Google profile picture, falling back to the account's
/// initials. The fallback carries the load too: the picture arrives over the network, so
/// there is always a moment — and, for an account without one, forever — where it is the
/// only thing to draw.
struct ProfileAvatarView: View {
    let account: AuthService.Account?
    var size: CGFloat = 60

    var body: some View {
        Group {
            if let url = account?.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        // Loading and failure look the same on purpose: a broken-image
                        // glyph in place of someone's face reads as a bug, initials don't.
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: some View {
        Circle()
            .fill(AppColors.brandBlue.opacity(0.2))
            .overlay(
                Text(initialsText)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundColor(AppColors.brandBlue)
            )
    }

    /// First letters of the display name, or the email's first letter when Google gave us
    /// no name. Two initials at most — more stops fitting in the circle.
    private var initialsText: String {
        let name = account?.displayName?.trimmingCharacters(in: .whitespaces) ?? ""
        let words = name.split(separator: " ").prefix(2)
        if !words.isEmpty {
            return words.compactMap { $0.first }.map(String.init).joined().uppercased()
        }
        guard let first = account?.email.first else { return "" }
        return String(first).uppercased()
    }
}

#Preview {
    VStack(spacing: 16) {
        ProfileAvatarView(account: .init(email: "anteater@uci.edu", displayName: "Peter Anteater", avatarURL: nil))
        ProfileAvatarView(account: .init(email: "anteater@uci.edu", displayName: nil, avatarURL: nil))
        ProfileAvatarView(account: nil)
    }
}
