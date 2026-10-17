import Foundation

/// A rolled-up read of recent crowd reports, used to drive the busyness meter.
struct BusynessSnapshot {
    let averageLevel: Int
    let reportCount: Int
    let lastUpdated: Date?

    static let empty = BusynessSnapshot(averageLevel: 0, reportCount: 0, lastUpdated: nil)
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
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw BackendError(statusCode: status, body: String(data: data, encoding: .utf8) ?? "<non-utf8 body>")
        }

        let decoded = try JSONDecoder().decode(CrowdLevelResponse.self, from: data)
        guard decoded.reportCount > 0 else { return .empty }

        return BusynessSnapshot(
            averageLevel: Int(decoded.level.rounded()),
            reportCount: decoded.reportCount,
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
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw BackendError(statusCode: status, body: String(data: data, encoding: .utf8) ?? "<non-utf8 body>")
        }
    }
}
