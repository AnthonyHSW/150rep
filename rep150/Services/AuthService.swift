import Foundation
import Supabase

/// Ensures a Supabase session exists, signing in anonymously if needed.
/// There's no user-facing login flow yet; the anonymous session just
/// gives us an access token to authorize API requests with.
enum AuthService {
    static func ensureSession() async throws -> Session {
        if let session = try? await supabase.auth.session {
            return session
        }
        return try await supabase.auth.signInAnonymously()
    }

    static func accessToken() async throws -> String {
        try await ensureSession().accessToken
    }
}
