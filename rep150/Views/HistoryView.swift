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
                                    CompletedSessionRow(session: session)
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

    private var durationLabel: String {
        let total = Int(session.duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private var volumeLabel: String {
        let volume = session.totalVolume
        return volume.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(volume)) kg"
            : String(format: "%.1f kg", volume)
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
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    HistoryView()
}
