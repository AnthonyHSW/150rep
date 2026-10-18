import SwiftUI
import Charts
import UIKit

struct LiveView: View {
    /// How long this device keeps showing your tap as the current answer. The backend
    /// stops counting a report toward the live average after half an hour and the submit
    /// upserts, so re-reporting replaces your row rather than adding one — this is purely
    /// about not leaving a stale tap highlighted as though it still spoke for right now.
    private static let reportLifetime: TimeInterval = 15 * 60

    @State private var snapshot = BusynessSnapshot.empty
    @State private var selectedReport: Int? = nil
    /// When `selectedReport` was tapped, so it can be aged out. Held separately from the
    /// selection because the view needs to expire it both on a timer and on foregrounding.
    @State private var reportedAt: Date? = nil
    @State private var expiryTask: Task<Void, Never>? = nil
    @State private var isSubmitting = false
    @State private var isRefreshing = false
    /// The last refused report, kept on screen until the next attempt. A refusal has to be
    /// said out loud: the buttons go back to looking untouched either way, so without this
    /// a blocked report is indistinguishable from one that quietly worked.
    @State private var reportFailure: CrowdReportFailure? = nil

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            // Scrolls rather than filling the screen: the leaderboard pages as it is
            // reached, so this page is now taller than one screenful by design. The
            // Spacers that used to center the meter are gone with it — they would push
            // the leaderboard off the bottom of the content, where nothing would ever
            // bring it into view.
            ScrollView {
                VStack(spacing: 20) {
                    // Live Busyness Meter
                    BusynessMeterSection(
                        snapshot: snapshot,
                        isRefreshing: isRefreshing,
                        onRefresh: handleForceRefresh
                    )

                    // Best Time Today
                    DailyTrafficChartSection(snapshot: snapshot)

                    // Quick Crowd Report
                    CrowdReportSection(
                        selectedReport: $selectedReport,
                        isSubmitting: isSubmitting,
                        failure: reportFailure,
                        onSubmit: handleReportSubmit
                    )

                    // Karma Leaderboard
                    LeaderboardSection()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                // Clears the floating tab bar, so the last row of the leaderboard can be
                // scrolled out from under it and actually read.
                .padding(.bottom, 24)
            }
            .background(AppColors.pageBackground)
            .navigationTitle("Arc Now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    LogoView()
                        .frame(width: 70, height: 28)
                }
            }
        }
        .task {
            await refreshSnapshot()
        }
        .onChange(of: scenePhase) { _, phase in
            // The expiry task can be starved while the app is suspended, so coming back to
            // the foreground is the other moment the selection has to be re-checked.
            if phase == .active { expireReportIfNeeded() }
        }
        .onDisappear {
            expiryTask?.cancel()
            expiryTask = nil
        }
    }

    private func handleReportSubmit(_ level: Int) {
        guard !isSubmitting else { return }
        isSubmitting = true
        reportFailure = nil

        Task {
            defer { isSubmitting = false }
            do {
                // Prove we are at the Arc before saying anything about how busy it is. The
                // device check is only the fast half of this — it runs first so a report
                // from across campus is refused with an explanation instead of a round
                // trip — and the backend repeats it on the coordinates it receives.
                let location = try await LocationService.shared.locationAtArc()
                try await BusynessService.submitReport(level: level, from: location)

                // Nothing of the tap shows until both halves have gone through, so a lit
                // button always stands for a report the backend actually took.
                selectedReport = level
                reportedAt = Date()
                scheduleReportExpiry()
                await refreshSnapshot()
            } catch {
                print("Failed to submit crowd report: \(error)")
                // Nothing of the tap survives a failed submit: leaving it highlighted would
                // claim a report the backend never took, and leaving `reportedAt` set would
                // schedule an expiry for a selection that is already gone.
                selectedReport = nil
                reportedAt = nil
                expiryTask?.cancel()
                expiryTask = nil
                reportFailure = CrowdReportFailure(error)
            }
        }
    }

    /// Arm a single timer to clear the selection once it ages out, replacing any timer left
    /// over from an earlier tap so the newest report is the one that sets the deadline.
    private func scheduleReportExpiry() {
        expiryTask?.cancel()

        guard let reportedAt else {
            expiryTask = nil
            return
        }

        let remaining = Self.reportLifetime - Date().timeIntervalSince(reportedAt)
        guard remaining > 0 else {
            expiryTask = nil
            expireReportIfNeeded()
            return
        }

        expiryTask = Task {
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            expireReportIfNeeded()
        }
    }

    /// Drop the selection if it has outlived `reportLifetime`; otherwise leave it and make
    /// sure a timer is still armed for whatever time it has left.
    private func expireReportIfNeeded() {
        guard let reportedAt else { return }

        if Date().timeIntervalSince(reportedAt) >= Self.reportLifetime {
            selectedReport = nil
            self.reportedAt = nil
            expiryTask?.cancel()
            expiryTask = nil
        } else if expiryTask == nil {
            scheduleReportExpiry()
        }
    }

    private func refreshSnapshot() async {
        do {
            snapshot = try await BusynessService.fetchCurrentBusyness()
        } catch {
            // Drop the old reading rather than leaving it on screen. Keeping it would show a
            // stale count and level as though they were current, which is the one thing the
            // meter must not do when it has just failed to confirm them.
            snapshot = .empty
            print("Failed to fetch busyness snapshot: \(error)")
        }
    }

    private func handleForceRefresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task {
            defer { isRefreshing = false }
            await refreshSnapshot()
        }
    }
}

// MARK: - Busyness Meter Section
struct BusynessMeterSection: View {
    let snapshot: BusynessSnapshot
    let isRefreshing: Bool
    let onRefresh: () -> Void

    private var hasData: Bool { snapshot.hasData }

    /// How often the "Checked …" label re-renders. A relative time is only true for the
    /// instant it was formatted, so the label has to be driven by a clock rather than
    /// computed once — left to redraw on its own it sat at "Checked 0 seconds ago" until
    /// some unrelated state change happened to rebuild the view.
    ///
    /// Every second, not every quarter-minute: anything coarser spends the first minute on
    /// one unchanging string, which is indistinguishable from the stuck label this replaced.
    /// It's one short caption redrawn while this screen is on top — the seconds are the whole
    /// point of showing the age at all.
    private static let updatedTick: TimeInterval = 1

    /// Abbreviated so it reads "5s ago" → "1m ago" → "2h ago": one compact style across every
    /// scale, and it moves within a second of a fetch instead of sitting on a bucket label.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// `lastUpdated` is when this device last fetched, not when anyone last reported — the
    /// endpoint returns no timestamp — so this says "Checked", not "Updated".
    ///
    /// The count is people, not submissions. `crowd_reports` is keyed by user and the
    /// submit upserts, so each person holds exactly one standing report however many
    /// times they tap — which is what keeps one keen reporter from swinging the
    /// average. Calling these "reports" read as a bug every time someone resubmitted.
    private func updatedText(asOf now: Date) -> String {
        guard let lastUpdated = snapshot.lastUpdated else { return "Nobody reporting yet" }

        switch snapshot.source {
        case .live(let count):
            let relative = Self.relativeFormatter.localizedString(for: lastUpdated, relativeTo: now)
            return "Checked \(relative) · \(count) \(count == 1 ? "person" : "people") reporting"
        case .typical:
            return "Typical for this hour · nobody reporting yet"
        case .unavailable:
            return "Nobody reporting yet"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 8) {
                HStack {
                    if hasData {
                        Text("\(snapshot.averageLevel)/10 · \(AppColors.crowdingLabel(for: snapshot.averageLevel))")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    } else {
                        Text("Gathering reports…")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .disabled(isRefreshing)
                    .opacity(isRefreshing ? 0.4 : 1.0)
                }

                BusynessMeterGauge(value: hasData ? Double(snapshot.averageLevel) : nil, maxValue: 10)
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(AppColors.contentSurface)
            .cornerRadius(20)
            .overlay {
                if !hasData {
                    ShimmerSweepOverlay(cornerRadius: 20)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: hasData)

            TimelineView(.periodic(from: snapshot.lastUpdated ?? .now, by: Self.updatedTick)) { context in
                Text(updatedText(asOf: context.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Busyness Shimmer (loading / no-data placeholder)
/// A translucent glass panel with a soft diagonal band of light sweeping across it,
/// shown over the gauge while there's no reading yet. Deliberately shows no numbers
/// so it can't be mistaken for a real value; the content underneath (the arc track)
/// still shows through, since the panel stays translucent.
struct ShimmerSweepOverlay: View {
    var cornerRadius: CGFloat = 16

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweepX: CGFloat = -0.6
    @State private var loopTask: Task<Void, Never>?

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.ultraThinMaterial.opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .overlay {
                GeometryReader { geo in
                    if reduceMotion {
                        // Static, softly illuminated placeholder — no motion.
                        RadialGradient(
                            colors: [Color.white.opacity(0.18), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: max(geo.size.width, geo.size.height) * 0.6
                        )
                    } else {
                        let diagonal = sqrt(geo.size.width * geo.size.width + geo.size.height * geo.size.height)

                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.35), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: geo.size.width * 0.4, height: diagonal * 1.4)
                        .rotationEffect(.degrees(45))
                        .blur(radius: 12)
                        .offset(x: sweepX * geo.size.width, y: -sweepX * geo.size.height)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onAppear(perform: startLoop)
            .onDisappear {
                loopTask?.cancel()
                loopTask = nil
            }
    }

    private func startLoop() {
        guard !reduceMotion, loopTask == nil else { return }
        loopTask = Task {
            while !Task.isCancelled {
                sweepX = -0.6
                withAnimation(.easeInOut(duration: 1.8)) {
                    sweepX = 1.6
                }
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
        }
    }
}

// MARK: - Busyness Meter Gauge
struct BusynessMeterGauge: View {
    /// `nil` means no reading yet — the track still renders, with liquid glass drifting over it.
    let value: Double?
    let maxValue: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            // Inset so the stroke's round caps and the marker dot stay
            // fully inside the gauge frame; the arc uses the full
            // available height as its vertical radius (a tall dome).
            let lineWidth: CGFloat = 12
            let inset = lineWidth / 2
            let radiusX = (width / 2 - inset) * 0.7
            let radiusY = height - inset
            let centerX = width / 2
            let centerY = height

            ZStack {
                // Background track
                EllipseArc(centerX: centerX, centerY: centerY, radiusX: radiusX, radiusY: radiusY)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                AppColors.quiet,
                                AppColors.moderate,
                                AppColors.busy,
                                AppColors.packed
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )

                if let value {
                    // Progress indicator
                    EllipseArc(centerX: centerX, centerY: centerY, radiusX: radiusX, radiusY: radiusY, fraction: min(value / maxValue, 1.0))
                        .stroke(
                            AppColors.crowdingColor(for: Int(value)),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )

                    // Marker
                    let angle = Angle.degrees(180 - (value / maxValue) * 180)
                    let markerX = centerX + radiusX * cos(angle.radians)
                    let markerY = centerY - radiusY * sin(angle.radians)
                    Circle()
                        .fill(AppColors.crowdingColor(for: Int(value)))
                        .frame(width: 12, height: 12)
                        .shadow(radius: 2)
                        .position(x: markerX, y: markerY)
                }
            }
            .frame(width: width, height: height)
            .overlay(alignment: .bottom) {
                if let value {
                    // Wait time, overlaid inside the semicircle
                    VStack(spacing: 2) {
                        Text(WaitTimeEstimate.forLevel(Int(value)).rangeText)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("wait")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }
}

// Draws an arc of an ellipse defined by an explicit center and radii,
// from the left point (fraction 0) to the right point (fraction 1),
// independent of the shape's own frame — avoids mismatches between
// the drawn geometry and the frame it's placed in.
struct EllipseArc: Shape {
    var centerX: CGFloat
    var centerY: CGFloat
    var radiusX: CGFloat
    var radiusY: CGFloat
    var fraction: CGFloat = 1.0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 100
        let endStep = Int(CGFloat(steps) * min(max(fraction, 0), 1))

        guard endStep > 0 else { return path }

        for i in 0...endStep {
            let t = CGFloat(i) / CGFloat(steps)
            let angle = CGFloat.pi - t * CGFloat.pi // 180° to 0°
            let x = centerX + radiusX * cos(angle)
            let y = centerY - radiusY * sin(angle)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

// MARK: - Daily Traffic Chart Section
struct DailyTrafficChartSection: View {
    /// The live reading, overlaid on the typical curve so the two can be compared.
    let snapshot: BusynessSnapshot

    /// The curve for today. Hardcoded sample data for now — see `DailyBusyness.sample`.
    private var busyness: DailyBusyness {
        .sample(for: DailyBusyness.day(for: Date()))
    }

    /// The current hour's bar, when there is a live reading to put over it. Both the bucket
    /// and the reading have to exist: nothing is "now" outside the reported hours, and with
    /// no reports in there's no actual to compare against.
    ///
    /// Only live reports qualify. A historical reading is drawn from the same typical data
    /// as the curve behind it, so overlaying it would plot the curve against itself — it
    /// would look like agreement where there is really just one number shown twice.
    private var actualBar: (label: String, value: Double)? {
        guard case .live = snapshot.source,
              let bar = hourlyTraffic.first(where: { $0.isNow })
        else { return nil }
        return (bar.label, Double(snapshot.averageLevel))
    }

    /// One bar per reported hour, with the bucket covering the current time marked so it
    /// can be picked out of the row.
    private var hourlyTraffic: [HourlyTraffic] {
        let curve = busyness
        let nowIndex = curve.index(forHourOf: Date())

        return curve.values.enumerated().map { index, value in
            HourlyTraffic(
                id: index,
                label: Self.label(forHour: curve.hour(at: index)),
                value: value,
                isNow: index == nowIndex
            )
        }
    }

    private var weekdayName: String {
        Date().formatted(.dateTime.weekday(.wide))
    }

    /// Compact enough that every third hour can be labelled without the axis colliding.
    private static func label(forHour hour: Int) -> String {
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        return "\(displayHour)\(hour < 12 ? "a" : "p")"
    }

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text("Typical \(weekdayName) pattern")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            VStack(spacing: 8) {
                Chart {
                    // Both series are drawn unstacked: they share the current hour's x
                    // position, and the default stacking would sit the live reading on top
                    // of the typical bar — showing their sum rather than the comparison.
                    ForEach(hourlyTraffic) { bar in
                        BarMark(
                            x: .value("Hour", bar.label),
                            y: .value("Typical", bar.value),
                            stacking: .unstacked
                        )
                        .foregroundStyle(
                            bar.isNow ? AppColors.brandBlue.opacity(0.55) : AppColors.brandBlue.opacity(0.25)
                        )
                    }

                    // The live reading, drawn narrow and solid over the current hour's bar so
                    // the gap between the two is the "busier/quieter than usual" read.
                    if let actualBar {
                        BarMark(
                            x: .value("Hour", actualBar.label),
                            y: .value("Actual", actualBar.value),
                            width: .fixed(6),
                            stacking: .unstacked
                        )
                        .foregroundStyle(AppColors.crowdingColor(for: snapshot.averageLevel))
                        .cornerRadius(3)
                    }
                }
                // Both series are crowd levels, so pin the axis to that range rather than
                // letting it rescale — otherwise the comparison shifts as the live value moves.
                .chartYScale(domain: 0...10)
                .chartXAxis {
                    // 18 bars is too many to label individually; every third hour reads
                    // cleanly and still lands on the first and last bar.
                    AxisMarks(values: .stride(by: 3)) { value in
                        if let hour = value.as(String.self) {
                            AxisValueLabel(hour, anchor: .top)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisValueLabel(anchor: .leading)
                    }
                }
                .frame(height: 140)

                HStack(spacing: 14) {
                    legendItem("Typical", color: AppColors.brandBlue.opacity(0.25))

                    if let actualBar {
                        legendItem(
                            "Now · \(Int(actualBar.value))/10",
                            color: AppColors.crowdingColor(for: snapshot.averageLevel)
                        )
                    }
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(16)
            .background(AppColors.contentSurface)
            .cornerRadius(20)
            .padding(.top, 8)
        }
    }

    /// A colour swatch and its caption. Built by hand rather than with `Label`, whose icon
    /// doesn't pick up a tint from `foregroundStyle` here — both swatches came out grey.
    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)

            Text(title)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Crowd Report Section
/// A report the app or the backend refused, reduced to what the section has to show: the
/// sentence to put on screen, and whether Settings is where it gets fixed.
struct CrowdReportFailure {
    let message: String
    let isPermissionProblem: Bool

    init(_ error: Error) {
        if let gateError = error as? LocationGateError {
            message = gateError.localizedDescription
            isPermissionProblem = gateError.isPermissionProblem
        } else {
            // Anything else is a network or backend fault, and naming it would only put
            // a status code in front of someone who wants to tap a button again.
            message = "Couldn't send your report. Try again in a moment."
            isPermissionProblem = false
        }
    }
}

struct CrowdReportSection: View {
    @Binding var selectedReport: Int?
    let isSubmitting: Bool
    /// The last refusal, or `nil` when the last attempt went through.
    let failure: CrowdReportFailure?
    let onSubmit: (Int) -> Void

    @Environment(\.openURL) private var openURL

    let reports = [
        (level: 2, label: "Quiet"),
        (level: 5, label: "Moderate"),
        (level: 7, label: "Busy"),
        (level: 9, label: "Packed"),
    ]

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            // The location check is the reason this asks "here now?" and means it, so say
            // up front that a report is checked rather than letting the first refusal be
            // where someone finds out.
            HStack(spacing: 6) {
                Text("Here now? How busy is it?")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)

                if isSubmitting {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            HStack(spacing: 8) {
                ForEach(reports, id: \.label) { report in
                    Button(action: {
                        onSubmit(report.level)
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "circle.fill")
                                .foregroundColor(AppColors.crowdingColor(for: report.level))
                                .font(.caption)

                            Text(report.label)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(
                            selectedReport == report.level
                                ? AppColors.crowdingColor(for: report.level).opacity(0.15)
                                : Color.clear
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    selectedReport == report.level
                                        ? AppColors.crowdingColor(for: report.level)
                                        : Color.gray.opacity(0.2),
                                    lineWidth: 1.5
                                )
                        )
                        .cornerRadius(10)
                        .foregroundColor(.primary)
                    }
                    .disabled(isSubmitting)
                }
            }
            .opacity(isSubmitting ? 0.5 : 1.0)

            if let failure {
                VStack(spacing: 6) {
                    Text(failure.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    // Only for the refusals a setting can actually clear — sending someone
                    // to Settings to fix standing in the wrong place would be a dead end.
                    if failure.isPermissionProblem,
                       let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        Button("Open Settings") { openURL(settingsURL) }
                            .font(.caption.weight(.semibold))
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: failure?.message)
        .padding(.bottom, 20)
    }
}

// MARK: - Data Models
/// One bar of the daily pattern chart.
struct HourlyTraffic: Identifiable {
    /// Index into the day's reported hours, so bars keep a stable identity as values change.
    let id: Int
    let label: String
    let value: Double
    /// Whether this bucket covers the current time.
    let isNow: Bool
}

#Preview {
    LiveView()
        .preferredColorScheme(nil)
}
