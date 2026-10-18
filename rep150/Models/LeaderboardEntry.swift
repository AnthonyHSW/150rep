import Foundation

/// One row of the karma leaderboard, exactly as the backend ranks it.
///
/// Like `LiveWorkout`, these rows belong to other people and are read-only: nothing here is
/// ever written back or stored on the device. The backend deliberately serves no email
/// addresses — a name, a picture, and a score are all a ranked list needs, and the name is
/// the one the account's own verified Supabase profile carries.
struct LeaderboardEntry: Identifiable, Decodable {
    /// The backend's own ranking, not this row's position in the array. Sent rather than
    /// derived so a tie or a gap reads the same here as it does server-side.
    let rank: Int
    let karma: Int
    /// Nullable: an account whose Supabase profile has no name still has a score worth
    /// ranking, which is what `displayName` falls back for.
    private let name: String?
    private let photoUrl: String?

    /// Ranks are unique within a response, and stay put as more pages load, so they're a
    /// stabler identity than an array index.
    var id: Int { rank }

    enum CodingKeys: String, CodingKey {
        case rank, karma
        case name = "display_name"
        case photoUrl = "photo_url"
    }

    /// Who the row belongs to. The neutral fallback is the backend's own: a profile with no
    /// name displays as "UCI Student" rather than exposing the address behind it.
    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? "UCI Student" : trimmed
    }

    /// Parsed late rather than at decode time, as in `LiveWorkout`: one malformed URL
    /// shouldn't fail the whole page, and a profile with no picture is an ordinary case.
    ///
    /// Non-HTTPS is dropped instead of loaded. The backend populates these from verified
    /// profile metadata and serves them over HTTPS; anything else arriving here is not
    /// something to go and fetch.
    var photoURL: URL? {
        guard let photoUrl, !photoUrl.isEmpty,
              let url = URL(string: photoUrl),
              url.scheme?.lowercased() == "https"
        else { return nil }
        return url
    }

    /// Initials for the avatar fallback, on the same rules as `ProfileAvatarView`.
    var initials: String {
        let words = displayName.split(separator: " ").prefix(2)
        return words.compactMap(\.first).map(String.init).joined().uppercased()
    }
}
