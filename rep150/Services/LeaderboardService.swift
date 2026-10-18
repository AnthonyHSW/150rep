import Foundation

/// Reads the karma leaderboard from the backend API.
///
/// Mirrors `MachineService`: the backend holds the service-level database access and the UCI
/// rule, so the call carries the Supabase token and routes a refusal back through
/// `AuthService`. Read-only — karma is awarded server-side and nothing here writes.
struct LeaderboardService {
    /// The largest page the endpoint serves. Asking for more is a 422, so the request is
    /// clamped to it rather than sent and refused.
    static let maximumLimit = 100

    /// The top `limit` users by karma, highest first, as the backend ranks them.
    ///
    /// The endpoint takes a count, not an offset, so a second page is read by asking for a
    /// longer list and keeping the rows past the ones already shown — see
    /// `LeaderboardSection.loadMore()`. That re-sends the rows already on screen, which is
    /// cheap at these sizes (100 rows at most, ever) and keeps ranks consistent within a
    /// single response instead of stitching pages that were ranked at different moments.
    static func fetchLeaderboard(limit: Int) async throws -> [LeaderboardEntry] {
        let clamped = min(max(limit, 1), maximumLimit)
        let request = try await authorizedRequest(
            path: "/v1/leaderboard?limit=\(clamped)",
            method: "GET"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try await validate(response, data: data)

        return try JSONDecoder().decode([LeaderboardEntry].self, from: data)
    }

    private static func authorizedRequest(path: String, method: String) async throws -> URLRequest {
        let token = try await AuthService.accessToken()

        var request = URLRequest(url: URL(string: path, relativeTo: APIConfig.baseURL)!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Same contract as `MachineService.validate`: tell `AuthService` first when the backend
    /// refuses the token, since a 403 is how the app learns the signed-in account isn't
    /// allowed — that rule lives server-side.
    private static func validate(_ response: URLResponse, data: Data) async throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            await AuthService.shared.handleRejection(statusCode: status)
            throw BackendError(
                statusCode: status,
                body: String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            )
        }
    }
}
