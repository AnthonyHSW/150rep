import SwiftUI

/// The karma leaderboard, ranked highest first.
///
/// Owns its own loading state rather than taking rows from `LiveView`: it is the only thing
/// on that screen that pages, and the rest of the page has nothing to do with it. Loads the
/// first ten and extends the list as the bottom of it comes into view.
struct LeaderboardSection: View {
    /// How many rows the first load asks for, and how many each extension adds.
    private static let pageSize = 10

    @State private var entries: [LeaderboardEntry] = []
    /// The count most recently requested. Not `entries.count` — a short response is how the
    /// section learns it has reached the end, so the two deliberately diverge there.
    @State private var requestedCount = 0
    @State private var isLoading = false
    /// False once a response comes back shorter than it was asked for, or once the
    /// endpoint's ceiling is reached. Stops the sentinel from asking forever.
    @State private var canLoadMore = true
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
                            // The sentinel is the last row itself rather than a spacer under
                            // it: a trailing view would also be on screen while the first
                            // page is still arriving, and would fire a second request for
                            // rows the first one is already fetching.
                            .onAppear {
                                guard index == entries.count - 1 else { return }
                                Task { await loadMore() }
                            }
                    }
                }

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                } else if hasFailed {
                    retryRow
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(AppColors.contentSurface)
        .cornerRadius(20)
        .task {
            // Only the first page; later ones are pulled by the sentinel. Guarded because
            // `.task` runs again whenever the view is reattached, and the rows already
            // loaded are the ones it would be refetching.
            guard entries.isEmpty, !isLoading else { return }
            await loadMore()
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

    /// Extend the list by one page, or load the first one.
    ///
    /// The endpoint pages by count rather than offset, so this asks for a longer list and
    /// replaces what it holds. The rows it already had come back identical — they are
    /// ranked in the same response as the new ones — so nothing on screen jumps.
    private func loadMore() async {
        guard !isLoading, canLoadMore, !hasFailed else { return }

        let target = min(requestedCount + Self.pageSize, LeaderboardService.maximumLimit)
        guard target > requestedCount else {
            canLoadMore = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await LeaderboardService.fetchLeaderboard(limit: target)
            entries = page
            requestedCount = target
            // Short of what was asked for means there is nobody else to rank; reaching the
            // endpoint's ceiling means there is nothing further it will serve.
            canLoadMore = page.count >= target && target < LeaderboardService.maximumLimit
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
