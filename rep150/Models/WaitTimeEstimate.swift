import Foundation

/// An estimated wait for equipment, translated from the busyness level.
///
/// The two ends are fixed points we are confident about: a quiet gym is a 0–2 minute
/// wait, and a packed one is about fifteen minutes. Everything between them is
/// interpolated linearly, which is a deliberate choice of the simplest curve that hits
/// both anchors — we have no measured wait data to justify anything more shaped. Tune
/// `quiet` and `packed` below and the whole scale moves with them.
///
/// The band widens as the gym fills (2 minutes across when quiet, 6 when packed)
/// because a busy floor is genuinely less predictable, not just slower.
struct WaitTimeEstimate: Equatable {
    /// Minutes at the optimistic end of the estimate.
    let lowMinutes: Int
    /// Minutes at the pessimistic end.
    let highMinutes: Int

    /// The wait at level 1, the quietest the meter reports.
    private static let quiet = (low: 0.0, high: 2.0)
    /// The wait at level 10, centred on the ~15 minutes a packed gym costs.
    private static let packed = (low: 12.0, high: 18.0)

    /// Translate a 1–10 busyness level into a wait. Levels outside that range are
    /// clamped: the meter never reports them, but a stray value should bend the scale
    /// rather than produce a negative wait.
    static func forLevel(_ level: Int) -> WaitTimeEstimate {
        let clamped = min(max(level, 1), 10)
        let progress = Double(clamped - 1) / 9.0

        return WaitTimeEstimate(
            lowMinutes: Int((quiet.low + (packed.low - quiet.low) * progress).rounded()),
            highMinutes: Int((quiet.high + (packed.high - quiet.high) * progress).rounded())
        )
    }

    /// Phrasing for the meter. A zero lower bound is written as "Under n min" rather
    /// than "0–n min", which reads like a broken range.
    var description: String {
        lowMinutes == 0
            ? "Under \(highMinutes) min wait"
            : "\(lowMinutes)–\(highMinutes) min wait"
    }
}
