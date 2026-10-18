import SwiftUI
import SwiftData

struct ProfileView: View {
    private let auth = AuthService.shared

    /// Every completed workout, filtered down to this week in `workoutsThisWeek`.
    ///
    /// The week boundary is deliberately *not* in the predicate: a `@Query` filter is built
    /// once when the view is created, and this screen lives for as long as the app does, so a
    /// baked-in "start of this week" would still be last week's Monday after midnight on
    /// Sunday. Filtering in Swift against a date read at render time is what keeps the count
    /// honest across a week rollover.
    @Query(
        filter: #Predicate<WorkoutSession> { $0.statusRaw == "completed" },
        sort: \WorkoutSession.startTime,
        order: .reverse
    )
    private var completedSessions: [WorkoutSession]

    @Environment(\.scenePhase) private var scenePhase

    @State private var isConfirmingSignOut = false

#if DEBUG
    /// Mirrors `LocationService.skipsLocationCheck`, which reads the same key straight out
    /// of `UserDefaults` — `@AppStorage` here is only so the toggle redraws.
    @AppStorage(PreferenceKey.skipLocationCheck) private var skipsLocationCheck = false
#endif

    /// Re-read when the app comes back to the foreground, so a week that turned over while
    /// the app was backgrounded resets the count.
    @State private var now = Date()

    private var workoutsThisWeek: Int {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        // Half-open on purpose: `dateInterval` gives the start of the *next* week as its end,
        // so `contains` would count a workout logged in the small hours of next Monday.
        return completedSessions.filter { $0.startTime >= week.start && $0.startTime < week.end }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    ProfileAvatarView(account: auth.account)

                    // The signed-in account, not a hardcoded one.
                    Text(auth.account?.displayName ?? "Signed in")
                        .font(.system(size: 18, weight: .semibold))

                    Text(auth.account?.email ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                // Matches the card below it. Without this the card hugged its contents, so
                // its width tracked the length of the signed-in email and the two cards
                // lined up only by coincidence.
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(AppColors.contentSurface)
                .cornerRadius(20)

                VStack(alignment: .center, spacing: 12) {
                    Text("This Week")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)

                    Text(workoutsThisWeek == 1 ? "1 workout completed" : "\(workoutsThisWeek) workouts completed")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(16)
                .background(AppColors.contentSurface)
                .cornerRadius(20)

#if DEBUG
                debugCard
#endif

                Spacer(minLength: 0)

                Button(role: .destructive) {
                    isConfirmingSignOut = true
                } label: {
                    Text("Sign Out")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.contentSurface)
                        .cornerRadius(16)
                }
            }
            .padding(16)
            .frame(maxHeight: .infinity)
            .background(AppColors.pageBackground)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { now = Date() }
            }
            .confirmationDialog(
                "Sign out of Arc Now?",
                isPresented: $isConfirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    Task { await auth.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Workouts saved on this device stay put. You will need to sign in again to report busyness.")
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    LogoView()
                        .frame(width: 70, height: 28)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                            .font(.headline)
                    }
                }
            }
        }
    }

#if DEBUG
    /// Debug-only controls, on the page rather than behind the gear: it exists to be
    /// switched on and off while working on crowd reports, and a release build never
    /// compiles it at all.
    private var debugCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $skipsLocationCheck) {
                Text("Skip Location Check")
                    .font(.system(size: 16, weight: .semibold))
            }
            .tint(AppColors.brandBlue)

            // Said plainly, because the reports are not pretend. They land in the same
            // table, move the live average, and earn karma like anyone else's.
            Text("Sends busyness reports as though you were at the Arc, skipping the location check. Debug builds only — the reports are real.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(AppColors.contentSurface)
        .cornerRadius(20)
    }
#endif
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss

    private let auth = AuthService.shared

    @AppStorage(PreferenceKey.weightUnit) private var weightUnit = WeightUnit.default
    @AppStorage(PreferenceKey.appearance) private var appearance = AppearanceSetting.system

    @State private var isConfirmingSignOut = false

    var body: some View {
        Form {
            Section("Account") {
                // The signed-in account, not a hardcoded address.
                Text(auth.account?.email ?? "Not signed in")
                    .foregroundColor(.secondary)
            }

            Section("Preferences") {
                Picker("Weight Units", selection: $weightUnit) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.name).tag(unit)
                    }
                }

                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceSetting.allCases) { setting in
                        Text(setting.name).tag(setting)
                    }
                }
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    isConfirmingSignOut = true
                }
            } footer: {
                // Switching units converts what is already recorded rather than relabelling
                // it, so say so — otherwise a history that suddenly reads 132 instead of 60
                // looks like the numbers were lost.
                Text("Weights are stored in kilograms and converted for display, so changing units never alters a recorded workout.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Sign out of Arc Now?",
            isPresented: $isConfirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task { await auth.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Workouts saved on this device stay put. You will need to sign in again to report busyness.")
        }
    }
}

#Preview {
    ProfileView()
}
