import Foundation
import Supabase

/// A rolled-up read of recent crowd reports, used to drive the busyness meter.
struct BusynessSnapshot {
    let averageLevel: Int
    let reportCount: Int
    let lastUpdated: Date?

    static let empty = BusynessSnapshot(averageLevel: 0, reportCount: 0, lastUpdated: nil)
}

/// Reads and writes crowd reports against the Supabase `crowd_reports` table.
struct BusynessService {
    /// Only reports within this window count toward the current reading.
    static let recentWindow: TimeInterval = 60 * 60

    static func fetchCurrentBusyness() async throws -> BusynessSnapshot {
        let since = Date().addingTimeInterval(-recentWindow)

        let reports: [CrowdReport] = try await supabase
            .from("crowd_reports")
            .select()
            .gte("created_at", value: since)
            .order("created_at", ascending: false)
            .execute()
            .value

        guard !reports.isEmpty else { return .empty }

        let average = reports.reduce(0) { $0 + $1.level } / reports.count
        return BusynessSnapshot(
            averageLevel: average,
            reportCount: reports.count,
            lastUpdated: reports.first?.createdAt
        )
    }

    static func submitReport(level: Int) async throws {
        try await supabase
            .from("crowd_reports")
            .insert(CrowdReportInsert(level: level))
            .execute()
    }
}
