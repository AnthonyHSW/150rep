import Foundation

/// Reads and writes machine availability through the backend API.
///
/// Mirrors `BusynessService`: the backend holds the service-level database access and the
/// UCI rule, so every call here carries the Supabase token and routes a refusal back through
/// `AuthService`.
struct MachineService {
    /// Every machine with its latest status, grouped by location as the backend orders them.
    static func fetchMachines() async throws -> [Machine] {
        let request = try await authorizedRequest(path: "/v1/machines", method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)
        try await validate(response, data: data)

        return try decoder.decode([Machine].self, from: data)
    }

    /// Adds a machine. Throws a `BackendError` with status 409 when the name is taken —
    /// names are unique server-side so the list can't fill with indistinguishable rows.
    @discardableResult
    static func addMachine(name: String, location: String?) async throws -> Machine {
        var request = try await authorizedRequest(path: "/v1/machines", method: "POST")
        request.httpBody = try JSONEncoder().encode(
            MachineCreate(name: name, location: location)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try await validate(response, data: data)

        return try decoder.decode(Machine.self, from: data)
    }

    /// Reports whether a machine is in use, returning it as the backend now holds it.
    @discardableResult
    static func updateStatus(machineId: Int, isInUse: Bool) async throws -> Machine {
        var request = try await authorizedRequest(
            path: "/v1/machines/\(machineId)/status",
            method: "PUT"
        )
        request.httpBody = try JSONEncoder().encode(MachineStatusUpdate(isInUse: isInUse))

        let (data, response) = try await URLSession.shared.data(for: request)
        try await validate(response, data: data)

        return try decoder.decode(Machine.self, from: data)
    }

    /// FastAPI serializes `datetime` as ISO 8601, and Postgres hands it fractional seconds —
    /// which the plain `.iso8601` strategy rejects outright.
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }

            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Not an ISO 8601 date: \(text)"
                )
            }
            return date
        }
        return decoder
    }()

    private static func authorizedRequest(path: String, method: String) async throws -> URLRequest {
        let token = try await AuthService.accessToken()

        var request = URLRequest(url: URL(string: path, relativeTo: APIConfig.baseURL)!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// Check a protected response, telling `AuthService` first when the backend refuses the
    /// token. Same contract as `BusynessService.validate`: a 403 is how the app learns the
    /// signed-in account isn't allowed, since the rule lives server-side.
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
