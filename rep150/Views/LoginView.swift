import SwiftUI

/// The sign-in wall. Everything in the app is behind an account now, so this is the
/// first thing a new or signed-out user sees.
struct LoginView: View {
    let auth: AuthService

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 24) {
                LogoView()
                    .frame(width: 140, height: 56)

                VStack(spacing: 8) {
                    Text("Sign in to Arc Now")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.primary)

                    Text("Use your UCI Google account to see live gym busyness and track your workouts.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                signInButton

                // Stated up front rather than only after a rejected sign-in, so nobody
                // gets through the Google flow before finding out their account qualifies.
                Label("@\(AuthService.requiredDomain) accounts only", systemImage: "graduationcap")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let errorMessage = auth.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(AppColors.packed)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .background(AppColors.contentSurface)
            .cornerRadius(24)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.pageBackground)
        .animation(.easeInOut(duration: 0.2), value: auth.errorMessage)
    }

    private var signInButton: some View {
        Button {
            Task { await auth.signInWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                if auth.isSigningIn {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "person.badge.key")
                }

                Text(auth.isSigningIn ? "Signing in…" : "Continue with Google")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppColors.brandBlue)
            .cornerRadius(14)
        }
        .disabled(auth.isSigningIn)
        .opacity(auth.isSigningIn ? 0.7 : 1)
    }
}

#Preview {
    LoginView(auth: AuthService.shared)
}
