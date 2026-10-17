import SwiftUI
import Charts

struct LiveView: View {
    @State private var snapshot = BusynessSnapshot.empty
    @State private var selectedReport: Int? = nil
    @State private var isSubmitting = false
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 0)

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
                    onSubmit: handleReportSubmit
                )

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxHeight: .infinity)
            .background(AppColors.pageBackground)
            .navigationTitle("Arc Now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    LogoView()
                        .frame(width: 70, height: 28)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("View Options", action: {})
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.headline)
                    }
                }
            }
        }
        .task {
            await refreshSnapshot()
        }
    }

    private func handleReportSubmit(_ level: Int) {
        guard !isSubmitting else { return }
        selectedReport = level
        isSubmitting = true

        Task {
            defer { isSubmitting = false }
            do {
                try await BusynessService.submitReport(level: level)
                await refreshSnapshot()
            } catch {
                print("Failed to submit crowd report: \(error)")
            }
        }
    }

    private func refreshSnapshot() async {
        do {
            snapshot = try await BusynessService.fetchCurrentBusyness()
        } catch {
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

    private var hasData: Bool { snapshot.reportCount > 0 }

    private var updatedText: String {
        guard let lastUpdated = snapshot.lastUpdated else { return "No recent reports" }
        let relative = RelativeDateTimeFormatter().localizedString(for: lastUpdated, relativeTo: Date())
        return "Updated \(relative) · \(snapshot.reportCount) recent report\(snapshot.reportCount == 1 ? "" : "s")"
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

            Text(updatedText)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
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
                        Text("~3–5 min")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
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
    private var actualBar: (label: String, value: Double)? {
        guard snapshot.reportCount > 0,
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

            Text("Sample data — live service not wired up yet")
                .font(.caption2)
                .foregroundColor(.secondary)

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
struct CrowdReportSection: View {
    @Binding var selectedReport: Int?
    let onSubmit: (Int) -> Void

    let reports = [
        (level: 2, label: "Quiet"),
        (level: 5, label: "Moderate"),
        (level: 7, label: "Busy"),
        (level: 9, label: "Packed"),
    ]

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Text("Here now? How busy is it?")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

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
                }
            }
        }
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
