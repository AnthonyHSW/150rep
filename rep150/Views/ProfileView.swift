import SwiftUI

struct ProfileView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    Circle()
                        .fill(AppColors.brandBlue.opacity(0.2))
                        .frame(width: 60, height: 60)

                    Text("Oliver Larsson")
                        .font(.system(size: 18, weight: .semibold))

                    Text("olarsson@uci.edu")
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
            }
            .padding(16)
            .frame(maxHeight: .infinity)
            .background(AppColors.pageBackground)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
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

    var body: some View {
        Form {
            Section("Account") {
                Text("olarsson@uci.edu")
            }

            Section("Preferences") {
                Picker("Weight Units", selection: .constant("Pounds")) {
                    Text("Pounds").tag("Pounds")
                    Text("Kilograms").tag("Kilograms")
                }

                Picker("Appearance", selection: .constant("System")) {
                    Text("System").tag("System")
                    Text("Light").tag("Light")
                    Text("Dark").tag("Dark")
                }
            }

            Section {
                Button("Sign Out", role: .destructive) {}
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ProfileView()
}
