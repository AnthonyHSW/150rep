import SwiftUI

/// The karma leaderboard, ranked highest first.
///
/// Owns its own loading state rather than taking rows from `LiveView`: it is the only thing
/// on that screen that pages, and the rest of the page has nothing to do with it. Loads the
/// first ten and extends the list as the bottom of it comes into view.
struct LeaderboardSection: View {
    /// Bumped by the page when something has happened that the standings should reflect —
    /// a crowd report going through, which is what earns karma. Taken as a value rather
    /// than exposing a reload method, so the only thing the caller can ask for is "read it
    /// again", and the paging state stays this view's business.
    var refreshTrigger: Int = 0

    /// How many rows the first load asks for, and how many each extension adds.
    private static let pageSize = 10

    @State private var entries: [LeaderboardEntry] = []
    /// The count most recently requested. Not `entries.count` — a short response is how the
    /// section learns it has reached the end, so the two deliberately diverge there.
    @State private var requestedCount = 0
    @State private var isLoading = false
    /// How many ranked users there are, once that is known — a response shorter than it was
    /// asked for is what proves it. Held rather than folded into a flag because collapsing
    /// the list must not forget it: `requestedCount` goes back down, and without this the
    /// card would offer to expand into rows it already knows aren't there.
    @State private var knownTotal: Int?
    /// The last failure, kept on screen until a retry. A leaderboard that simply stays
    /// empty is indistinguishable from one nobody has scored on yet.
    @State private var hasFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if entries.isEmpty {
                placeholder
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().padding(.leading, 44)
                        }

                        LeaderboardRow(entry: entry)
                    }
                }

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                } else if hasFailed {
                    retryRow
                } else {
                    expandControls
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(AppColors.contentSurface)
        .cornerRadius(20)
        .task {
            // Only the first page; the rest is asked for by the button. Guarded because
            // `.task` runs again whenever the view is reattached, and the rows already
            // loaded are the ones it would be refetching.
            guard entries.isEmpty, !isLoading else { return }
            await loadMore()
        }
        .task(id: refreshTrigger) {
            // Skips the initial value, which `.task` above has already covered — this one
            // fires on every change *and* on first appearance.
            guard refreshTrigger != 0 else { return }
            await reload()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Karma Leaderboard")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            Text("Most karma earned at the Arc")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// What stands in before the first page lands — a spinner while it's in flight, and
    /// otherwise a sentence saying which of the two empty cases this is.
    @ViewBuilder
    private var placeholder: some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading the leaderboard…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } else if hasFailed {
            retryRow
        } else {
            Text("Nobody has earned karma yet.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.vertical, 8)
        }
    }

    /// Expand and collapse. Shown together once the list has grown, so the way back is in
    /// the same place as the way down — the card is tall by then, and the only other way to
    /// shrink it would be leaving the screen.
    @ViewBuilder
    private var expandControls: some View {
        HStack(spacing: 16) {
            if canLoadMore {
                Button {
                    Task { await loadMore() }
                } label: {
                    Label("Show More", systemImage: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
            }

            if entries.count > Self.pageSize {
                Button(action: collapse) {
                    Label("Show Less", systemImage: "chevron.up")
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .tint(AppColors.brandBlue)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
    }

    private var retryRow: some View {
        HStack(spacing: 8) {
            Text("Couldn't load the leaderboard.")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Retry") {
                Task {
                    // A failure leaves `canLoadMore` alone, so the retry picks up at the
                    // same page the failed attempt was asking for.
                    hasFailed = false
                    await loadMore()
                }
            }
            .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    /// Whether there is anything further to show: rows the endpoint will still serve, and
    /// that it hasn't already told us don't exist.
    private var canLoadMore: Bool {
        guard requestedCount < LeaderboardService.maximumLimit else { return false }
        guard let knownTotal else { return true }
        return requestedCount < knownTotal
    }

    /// Extend the list by one page, or load the first one.
    private func loadMore() async {
        guard canLoadMore || entries.isEmpty, !hasFailed else { return }

        let target = min(requestedCount + Self.pageSize, LeaderboardService.maximumLimit)
        guard target > requestedCount else { return }

        await load(limit: target)
    }

    /// Back to the first page, without a request: these rows were ranked in the same
    /// response as the ones being dropped, so what's left is already the top ten.
    private func collapse() {
        entries = Array(entries.prefix(Self.pageSize))
        requestedCount = Self.pageSize
    }

    /// Re-read however far the list has been expanded. Karma moves people between ranks
    /// rather than adding rows, so collapsing back to ten on every report would fold up a
    /// list the user had deliberately opened.
    private func reload() async {
        await load(limit: max(requestedCount, Self.pageSize))
    }

    /// Fetch `limit` rows and replace what's held.
    ///
    /// The endpoint pages by count rather than offset, so a longer list is how a further
    /// page is read. Everything comes back ranked in one response, so the rows already on
    /// screen can't disagree with the new ones and nothing jumps.
    private func load(limit: Int) async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await LeaderboardService.fetchLeaderboard(limit: limit)
            entries = page
            requestedCount = limit
            hasFailed = false
            // Short of what was asked for is the only evidence of the end there is — the
            // response carries no total — so a full page leaves the question open.
            if page.count < limit { knownTotal = page.count }
        } catch {
            print("Failed to load leaderboard: \(error)")
            hasFailed = true
        }
    }
}

// MARK: - Row

/// One ranked user: where they place, who they are, and how much karma they hold.
private struct LeaderboardRow: View {
    let entry: LeaderboardEntry

    /// The top three are weighted rather than coloured in. The theme reserves its crowding
    /// colours for crowd severity and rules out gold as decoration, so rank reads through
    /// type here instead.
    private var isTopThree: Bool { entry.rank <= 3 }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.system(size: 15, weight: isTopThree ? .bold : .regular))
                .monospacedDigit()
                .foregroundColor(isTopThree ? AppColors.brandBlue : .secondary)
                .frame(width: 24, alignment: .trailing)

            avatar

            Text(entry.displayName)
                .font(.system(size: 15, weight: isTopThree ? .semibold : .regular))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Text(entry.karma.formatted())
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(.primary)

                Text("karma")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    /// The user's profile picture, or their initials. Same fallback as `ProfileAvatarView`
    /// and `LiveWorkoutAvatar`: loading and failure look alike, because a broken-image glyph
    /// where a face should be reads as a bug.
    private var avatar: some View {
        Group {
            if let url = entry.photoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }

    private var initials: some View {
        Circle()
            .fill(AppColors.brandBlue.opacity(0.2))
            .overlay(
                Text(entry.initials)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.brandBlue)
            )
    }
}

#Preview {
    ScrollView {
        LeaderboardSection()
            .padding(16)
    }
    .background(AppColors.pageBackground)
}
