import Foundation

/// A day-of-week busyness curve: one value per hour, as returned by the busyness service
/// for a requested weekday — `{"e": 0, "values": [0.8, 1.2, ...]}`.
///
/// The service reports 18 hourly buckets starting at `startHour`, so `values[0]` covers
/// 6 AM and `values[17]` covers 11 PM.
struct DailyBusyness: Decodable {
    /// Clock hour the first value covers.
    static let startHour = 6

    /// Weekday the curve describes, echoing the request: 0 is Sunday through 6 is Saturday.
    let day: Int
    let values: [Double]

    enum CodingKeys: String, CodingKey {
        case day = "e"
        case values
    }
}

extension DailyBusyness {
    /// Clock hour (24-hour) the value at `index` covers.
    func hour(at index: Int) -> Int {
        Self.startHour + index
    }

    /// The bucket covering `date`, or `nil` when the time of day falls outside the hours
    /// the service reports — nothing is "now" at 3 AM.
    func index(forHourOf date: Date, calendar: Calendar = .current) -> Int? {
        let index = calendar.component(.hour, from: date) - Self.startHour
        return values.indices.contains(index) ? index : nil
    }

    /// Weekday index for `date` in the service's numbering (0 = Sunday).
    static func day(for date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: date) - 1
    }
}

extension DailyBusyness {
    /// Stand-in curve used until the day-of-week service is reachable from the app. Shaped
    /// like a real response so swapping in the fetch doesn't touch the chart.
    static func sample(for day: Int) -> DailyBusyness {
        DailyBusyness(
            day: day,
            values: [
                0.8, 1.2, 2.2, 3.8, 5.0, 5.5, 5.2, 4.5, 4.0,
                3.5, 3.0, 2.4, 1.8, 1.2, 0.8, 0.5, 0.3, 0.2,
            ]
        )
    }
}
