import Foundation

/// A rolled-up read of the current crowd level, used to drive the busyness meter.
struct BusynessSnapshot {
    /// Where `averageLevel` came from. The backend serves live votes when it has any from
    /// the last half hour and otherwise falls back to the hour's historical schedule, and
    /// the two must not be presented as the same thing: one is what people report right
    /// now, the other is only what this hour usually looks like.
    enum Source: Equatable {
        /// An average of live reports. The associated value counts *people*, not
        /// submissions: `crowd_reports` is keyed by user and the submit upserts, so
        /// resubmitting replaces your row rather than adding one.
        case live(reporterCount: Int)
        /// The historical figure for this hour, standing in because no live reports exist.
        case typical
        /// Nothing to show at all.
        case unavailable
    }

    let averageLevel: Int
    let source: Source
    let lastUpdated: Date?

    static let empty = BusynessSnapshot(averageLevel: 0, source: .unavailable, lastUpdated: nil)

    /// Whether there is a level worth putting on the meter, live or historical.
    var hasData: Bool { source != .unavailable }

    /// How many people back this reading; zero when it is historical or absent.
    var reporterCount: Int {
        if case .live(let count) = source { return count }
        return 0
    }
}

struct BackendError: LocalizedError {
    let statusCode: Int
    let body: String

    var errorDescription: String? {
        "Backend returned \(statusCode): \(body)"
    }
}

/// Reads and writes busyness through the backend API, which holds the service-level DB access.
struct BusynessService {
    static func fetchCurrentBusyness() async throws -> BusynessSnapshot {
        let token = try await AuthService.accessToken()

        var request = URLRequest(url: URL(string: "/v1/crowd-level", relativeTo: APIConfig.baseURL)!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try await validate(response, data: data)

        let decoded = try JSONDecoder().decode(CrowdLevelResponse.self, from: data)

        // A level with a zero count is not an empty response: that is how the backend
        // returns the hour's historical figure when nobody has reported in the last half
        // hour. Only a missing level means there is genuinely nothing to show — outside
        // the hours the schedule covers, for instance.
        guard let level = decoded.level else { return .empty }

        return BusynessSnapshot(
            averageLevel: Int(level.rounded()),
            source: decoded.reportCount > 0 ? .live(reporterCount: decoded.reportCount) : .typical,
            lastUpdated: Date()
        )
    }

    static func submitReport(level: Int) async throws {
        let token = try await AuthService.accessToken()

        var request = URLRequest(url: URL(string: "/v1/crowd-reports", relativeTo: APIConfig.baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CrowdReportInsert(level: level))

        let (data, response) = try await URLSession.shared.data(for: request)
        try await validate(response, data: data)
    }

    /// Check a protected response, telling `AuthService` first when the backend refuses
    /// the token. The UCI rule is enforced server-side, so a 403 here is how the app
    /// learns the signed-in account is not allowed — it has no way to know in advance.
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
