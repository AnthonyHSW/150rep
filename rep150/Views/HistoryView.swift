import SwiftUI
import SwiftData

/// Every completed workout, newest first.
///
/// Driven straight off the model with `@Query`, so finishing a workout lands here the
/// moment `WorkoutStore.finish(_:)` flips its status — there's no hand-off to maintain
/// between the active session and this tab.
struct HistoryView: View {
    @Query(
        filter: #Predicate<WorkoutSession> { $0.statusRaw == "completed" },
        sort: \WorkoutSession.startTime,
        order: .reverse
    )
    private var completedSessions: [WorkoutSession]

    @Environment(\.modelContext) private var modelContext
    @State private var editingViewModel: ActiveWorkoutViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if completedSessions.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(groupedByMonth, id: \.month) { group in
                            Section(group.month) {
                                ForEach(group.sessions) { session in
                                    Button {
                                        openEditor(for: session)
                                    } label: {
                                        CompletedSessionRow(session: session)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .listRowBackground(AppColors.contentSurface)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.pageBackground)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    LogoView()
                        .frame(width: 70, height: 28)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !completedSessions.isEmpty {
                        Text(completedSessions.count == 1 ? "1 workout" : "\(completedSessions.count) workouts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .fullScreenCover(item: $editingViewModel) { viewModel in
            ActiveWorkoutView(viewModel: viewModel)
        }
    }

    /// Reopens a finished workout in the active-workout screen, with its clocks stopped.
    private func openEditor(for session: WorkoutSession) {
        editingViewModel = ActiveWorkoutViewModel(
            session: session,
            store: WorkoutStore(modelContext: modelContext),
            mode: .editing
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No workouts yet")
                .font(.system(size: 17, weight: .semibold))
            Text("Finish a workout and it'll show up here.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(24)
    }

    private var groupedByMonth: [(month: String, sessions: [WorkoutSession])] {
        let groups = Dictionary(grouping: completedSessions) { session in
            session.startTime.formatted(.dateTime.month(.wide).year())
        }
        // `completedSessions` is already newest-first, so ordering the groups by their
        // newest member keeps the months in the same order as the sessions inside them.
        return groups
            .map { (month: $0.key, sessions: $0.value) }
            .sorted { ($0.sessions.first?.startTime ?? .distantPast) > ($1.sessions.first?.startTime ?? .distantPast) }
    }
}

struct CompletedSessionRow: View {
    let session: WorkoutSession

    @AppStorage(PreferenceKey.weightUnit) private var weightUnit = WeightUnit.default

    @State private var thumbnail: UIImage?

    private var photos: [WorkoutPhoto] { session.orderedPhotos }

    private var durationLabel: String {
        let total = Int(session.duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private var volumeLabel: String {
        "\(weightUnit.displayText(fromKilograms: session.totalVolume)) \(weightUnit.abbreviation)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.title)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text(session.startTime.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("\(durationLabel) · \(volumeLabel) · \(session.totalCompletedSets) sets")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .monospacedDigit()

            if !session.exercises.isEmpty {
                Text(session.exercises.sorted { $0.orderIndex < $1.orderIndex }
                    .map(\.name)
                    .joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .bottomTrailing) {
                        // Only the first photo is shown, so say when there are others behind
                        // it rather than implying the workout had just the one.
                        if photos.count > 1 {
                            Label("\(photos.count)", systemImage: "photo.on.rectangle")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.55), in: Capsule())
                                .padding(8)
                        }
                    }
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 2)
        // Keyed on the filename so the thumbnail reloads if the first photo is replaced, and
        // isn't redecoded on every redraw.
        .task(id: photos.first?.filename) {
            await loadThumbnail()
        }
    }

    /// Decodes the first photo at list-row size, off the main actor — these files are up to
    /// 1920px, and decoding one per row during scrolling would land squarely on the main
    /// thread.
    private func loadThumbnail() async {
        guard let filename = photos.first?.filename else {
            thumbnail = nil
            return
        }

        thumbnail = await Task.detached(priority: .userInitiated) {
            WorkoutPhotoFileManager.shared.thumbnail(filename: filename, maxPixelSize: 600)
        }.value
    }
}

#Preview {
    HistoryView()
}
