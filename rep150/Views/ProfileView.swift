import SwiftUI

struct ProfileView: View {
    private let auth = AuthService.shared

    @State private var isConfirmingSignOut = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    Circle()
                        .fill(AppColors.brandBlue.opacity(0.2))
                        .frame(width: 60, height: 60)

                    // The signed-in account, not a hardcoded one.
                    Text(auth.account?.displayName ?? "Signed in")
                        .font(.system(size: 18, weight: .semibold))

                    Text(auth.account?.email ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(20)
                .background(AppColors.contentSurface)
                .cornerRadius(20)

                VStack(alignment: .center, spacing: 12) {
                    Text("This Week")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)

                    Text("0 workouts completed")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(16)
                .background(AppColors.contentSurface)
                .cornerRadius(20)

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
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss

    private let auth = AuthService.shared

    @AppStorage(PreferenceKey.weightUnit) private var weightUnit = WeightUnit.kilograms
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
