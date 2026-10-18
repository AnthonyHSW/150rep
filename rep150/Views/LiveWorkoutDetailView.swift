import SwiftUI

/// Somebody else's workout, as it stands right now.
///
/// Read-only throughout, and not a reuse of `ActiveWorkoutView`: that screen's entire job is
/// editing — tapping a set completes it, the keyboard is one tap away, and the toolbar
/// offers Finish. None of that belongs on a workout the viewer doesn't own, so this is its
/// own, much smaller screen rather than `ActiveWorkoutView` with half of it switched off.
struct LiveWorkoutDetailView: View {
    let workout: LiveWorkout

    @AppStorage(PreferenceKey.weightUnit) private var weightUnit = WeightUnit.default
    @Environment(\.dismiss) private var dismiss

    /// Ticks the elapsed-time label. The sets themselves refresh when the feed behind this
    /// screen does, which is a network round trip; this is only the clock.
    @State private var now = Date()

    private var elapsed: TimeInterval { now.timeIntervalSince(workout.startTime) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    if workout.exercises.isEmpty {
                        Text("No exercises logged yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 24)
                    } else {
                        ForEach(workout.orderedExercises) { exercise in
                            LiveExerciseCard(exercise: exercise, weightUnit: weightUnit)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity)
            .background(AppColors.pageBackground)
            .navigationTitle(workout.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .task {
            // Stops on its own when the screen goes away, since the task is cancelled with it.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                now = Date()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                LiveWorkoutAvatar(workout: workout, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.ownerDisplayName)
                        .font(.system(size: 17, weight: .semibold))
                    LiveNowLabel()
                }

                Spacer()
            }

            Divider()

            HStack {
                statistic(elapsed.workoutClockText, label: "Elapsed")
                Spacer()
                statistic("\(workout.totalCompletedSets)", label: "Sets")
                Spacer()
                statistic(
                    "\(weightUnit.displayText(fromKilograms: workout.totalVolume)) \(weightUnit.abbreviation)",
                    label: "Volume"
                )
            }
        }
        .padding(16)
        .background(AppColors.contentSurface)
        .cornerRadius(12)
    }

    private func statistic(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Exercise card

/// One exercise and its sets. Flat text rather than the editable grid `ExerciseCardView`
/// draws — there is nothing here to tap.
private struct LiveExerciseCard: View {
    let exercise: LiveExercise
    let weightUnit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ExerciseIconView(imageName: exercise.imageName, size: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text(exercise.name)
                        .font(.system(size: 16, weight: .semibold))
                    Text(exercise.primaryMuscle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            ForEach(exercise.orderedSets) { set in
                HStack(spacing: 10) {
                    // Only completed sets get the filled mark. An untouched set row is a
                    // data-entry scaffold on the owner's screen, not work that happened, and
                    // showing it as done would overstate what they've actually lifted.
                    Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundColor(set.isCompleted ? AppColors.brandBlue : .secondary.opacity(0.4))

                    Text("Set \(set.setNumber)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    if set.type != .normal {
                        Text(set.type.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                    }

                    Spacer()

                    Text(measurement(of: set))
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(set.isCompleted ? .primary : .secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.contentSurface)
        .cornerRadius(12)
    }

    /// What the set amounted to, in whichever terms its exercise is measured. An em dash for
    /// a set with nothing filled in — the owner is mid-workout, so blanks are expected, and
    /// "0 kg × 0" would read as a set they did and got nothing out of.
    private func measurement(of set: LiveSet) -> String {
        if exercise.isCardio {
            guard let seconds = set.durationSeconds else { return "—" }
            return TimeInterval(seconds).workoutClockText
        }

        guard let weight = set.weight, let reps = set.reps else { return "—" }
        return "\(weightUnit.displayText(fromKilograms: weight)) \(weightUnit.abbreviation) × \(reps)"
    }
}

// MARK: - Shared pieces

/// The owner's picture, or their initials. Mirrors `ProfileAvatarView`, which can only draw
/// the *signed-in* account — these are other people, and their name and picture arrive on
/// the workout row rather than from `AuthService`.
struct LiveWorkoutAvatar: View {
    let workout: LiveWorkout
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let url = workout.ownerAvatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        // Loading and failure look alike on purpose, as in ProfileAvatarView:
                        // a broken-image glyph where a face should be reads as a bug.
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
                Text(workout.ownerInitials)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundColor(AppColors.brandBlue)
            )
    }
}

/// The pulsing "Live" marker. Its own view so the row and the detail header can't drift.
struct LiveNowLabel: View {
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(AppColors.packed)
                .frame(width: 7, height: 7)
                .opacity(isPulsing ? 0.35 : 1)
                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isPulsing)

            Text("Live")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .onAppear { isPulsing = true }
    }
}
