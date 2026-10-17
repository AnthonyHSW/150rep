import Foundation
import Supabase

/// Errors surfaced by the sign-in flow that are ours rather than Supabase's.
enum AuthServiceError: LocalizedError {
    case notSignedIn
    /// The backend refused this account. It owns the UCI rule, so it decides.
    case accountNotPermitted

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You need to sign in first."
        case .accountNotPermitted:
            return "That account can't use Arc Now. Sign in with your @\(AuthService.requiredDomain) address."
        }
    }
}

/// Owns the signed-in state for the whole app.
///
/// Supabase Auth is the source of truth: it persists the session across launches and
/// renews the access token on its own, so there is no refresh call to make from here.
/// This type's job is to mirror that state into something SwiftUI can gate on. Whether
/// an account is actually allowed is the backend's call, not ours: it checks the UCI
/// domain when it verifies the token, and we react to its answer in `handleRejection`.
@MainActor
@Observable
final class AuthService {
    /// Who is signed in, as far as the UI needs to know.
    struct Account: Equatable {
        let email: String
        /// The name Google supplied, when it supplied one.
        let displayName: String?
    }

    enum State: Equatable {
        /// Checking for a stored session. Distinct from `signedOut` so the gate can wait
        /// rather than flashing the login screen at every launch.
        case restoring
        case signedOut
        case signedIn(Account)
    }

    static let shared = AuthService()

    /// Named in the sign-in copy so users know which account to pick. This is wording
    /// only — the backend is what actually enforces the restriction.
    static let requiredDomain = "uci.edu"

    /// Where Google sends the browser back to. The scheme is registered in Info.plist and
    /// allowlisted in the Supabase dashboard; `signInWithOAuth` derives the
    /// ASWebAuthenticationSession callback scheme from it.
    private static let redirectURL = URL(string: "rep150://auth-callback")!

    private(set) var state: State = .restoring
    private(set) var isSigningIn = false
    private(set) var errorMessage: String?

    private var watchTask: Task<Void, Never>?

    private init() {}

    /// Begin mirroring Supabase's auth state. Safe to call more than once.
    func start() {
        guard watchTask == nil else { return }

        watchTask = Task { [weak self] in
            for await (_, session) in supabase.auth.authStateChanges {
                await self?.apply(session)
            }
        }
    }

    /// Run the Google flow, then hold the result to the UCI rule.
    func signInWithGoogle() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let session = try await supabase.auth.signInWithOAuth(
                provider: .google,
                redirectTo: Self.redirectURL
            )
            await apply(session)
        } catch is CancellationError {
            // The user dismissed the browser sheet; that is not a failure worth reporting.
        } catch {
            // ASWebAuthenticationSession reports a plain cancel as an error too.
            if Self.isUserCancellation(error) { return }
            errorMessage = error.localizedDescription
            state = .signedOut
        }
    }

    func signOut() async {
        try? await supabase.auth.signOut()
        state = .signedOut
        errorMessage = nil
    }

    /// Mirror a Supabase session into our state. Any real signed-in account is accepted
    /// here; the backend rejects the ones it will not serve, and `handleRejection` turns
    /// that answer into a sign-out. Duplicating the domain rule on the client would only
    /// create a second place for it to drift out of step.
    private func apply(_ session: Session?) async {
        guard let session else {
            state = .signedOut
            return
        }

        // Sessions left over from the anonymous era carry no email. They are not a
        // rejected sign-in, just an obsolete one, so clear them quietly rather than
        // showing a first-time user an error they did nothing to cause.
        guard !session.user.isAnonymous, let email = session.user.email else {
            try? await supabase.auth.signOut()
            state = .signedOut
            return
        }

        state = .signedIn(
            Account(
                email: email,
                displayName: session.user.userMetadata["full_name"]?.stringValue
            )
        )
        errorMessage = nil
    }

    /// The signed-in account, or nil in every other state.
    var account: Account? {
        if case .signedIn(let account) = state { return account }
        return nil
    }

    /// Called when a protected request comes back unauthorized.
    ///
    /// 403 means the token was valid but the backend will not serve this account —
    /// the UCI check living there now — so the user is told why. 401 means the token
    /// itself is no longer good, which is not the user's doing and needs no explanation,
    /// just a fresh sign-in. Either way the session goes, so the app cannot sit on a
    /// token the server has already refused.
    func handleRejection(statusCode: Int) async {
        guard statusCode == 401 || statusCode == 403 else { return }

        try? await supabase.auth.signOut()
        state = .signedOut
        errorMessage = statusCode == 403
            ? AuthServiceError.accountNotPermitted.localizedDescription
            : nil
    }

    private static func isUserCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        // ASWebAuthenticationSessionErrorCodeCanceledLogin
        return nsError.domain == "com.apple.AuthenticationServices.WebAuthenticationSession"
            && nsError.code == 1
    }
}

// MARK: - Tokens for API requests
extension AuthService {
    /// The bearer token for protected backend requests. Supabase refreshes it on read when
    /// it has expired, so callers never deal with renewal themselves.
    static func accessToken() async throws -> String {
        guard let session = try? await supabase.auth.session else {
            throw AuthServiceError.notSignedIn
        }
        return session.accessToken
    }

    /// The signed-in user's id, used to scope per-user storage paths.
    static func currentUserId() async throws -> UUID {
        guard let session = try? await supabase.auth.session else {
            throw AuthServiceError.notSignedIn
        }
        return session.user.id
    }
}
