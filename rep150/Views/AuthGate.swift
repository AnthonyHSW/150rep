import SwiftUI

/// Decides whether the app or the login wall is on screen.
///
/// Every tab behind this gate talks to the backend with the signed-in user's token, so
/// the gate wraps the whole `ContentView` rather than individual tabs.
struct AuthGate: View {
    let auth: AuthService

    var body: some View {
        switch auth.state {
        case .restoring:
            // Supabase restores a stored session asynchronously. Waiting here keeps a
            // returning user from seeing the login screen flash before their session
            // loads, which would read as having been signed out.
            RestoringSessionView()
                .transition(.opacity)

        case .signedOut:
            LoginView(auth: auth)
                .transition(.opacity)

        case .signedIn:
            ContentView()
                .transition(.opacity)
        }
    }
}

/// Launch placeholder shown while a stored session is being restored.
private struct RestoringSessionView: View {
    var body: some View {
        VStack(spacing: 20) {
            LogoView()
                .frame(width: 140, height: 56)

            ProgressView()
                .tint(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.pageBackground)
    }
}
