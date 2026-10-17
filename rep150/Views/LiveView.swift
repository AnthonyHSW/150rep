import SwiftUI
import Charts

struct LiveView: View {
    @State private var snapshot = BusynessSnapshot.empty
    @State private var selectedReport: Int? = nil
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 0)

                // Live Busyness Meter
                BusynessMeterSection(snapshot: snapshot)

                // Best Time Today
                DailyTrafficChartSection()

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
}

// MARK: - Busyness Meter Section
struct BusynessMeterSection: View {
    let snapshot: BusynessSnapshot

    private var updatedText: String {
        guard let lastUpdated = snapshot.lastUpdated else { return "No recent reports" }
        let relative = RelativeDateTimeFormatter().localizedString(for: lastUpdated, relativeTo: Date())
        return "Updated \(relative) · \(snapshot.reportCount) recent report\(snapshot.reportCount == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 8) {
                Text("\(snapshot.averageLevel)/10 · \(AppColors.crowdingLabel(for: snapshot.averageLevel))")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                BusynessMeterGauge(value: Double(snapshot.averageLevel), maxValue: 10)
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(AppColors.contentSurface)
            .cornerRadius(20)

            Text(updatedText)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Busyness Meter Gauge
struct BusynessMeterGauge: View {
    let value: Double
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
            .frame(width: width, height: height)
            .overlay(alignment: .bottom) {
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
    let hourlyData = [
        ChartData(hour: "12 AM", traffic: 2),
        ChartData(hour: "2 AM", traffic: 1),
        ChartData(hour: "4 AM", traffic: 1),
        ChartData(hour: "6 AM", traffic: 3),
        ChartData(hour: "8 AM", traffic: 6),
        ChartData(hour: "10 AM", traffic: 8),
        ChartData(hour: "12 PM", traffic: 9),
        ChartData(hour: "2 PM", traffic: 7),
        ChartData(hour: "4 PM", traffic: 8),
        ChartData(hour: "6 PM", traffic: 6),
        ChartData(hour: "8 PM", traffic: 3),
        ChartData(hour: "10 PM", traffic: 2),
    ]

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Text("Usually quieter after 8 PM")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            VStack(spacing: 8) {
                Chart(hourlyData) { data in
                    BarMark(
                        x: .value("Hour", data.hour),
                        y: .value("Traffic", data.traffic)
                    )
                    .foregroundStyle(
                        data.hour == "6 PM"
                            ? AppColors.brandBlue.opacity(0.8)
                            : AppColors.brandBlue.opacity(0.3)
                    )
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: 2)) { value in
                        if let hour = value.as(String.self) {
                            AxisValueLabel(hour, anchor: .top)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 5, 10]) { value in
                        AxisGridLine()
                        AxisValueLabel(anchor: .leading)
                    }
                }
                .frame(height: 140)

                HStack(spacing: 16) {
                    Label("Typical traffic", systemImage: "square.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label("Now", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(16)
            .background(AppColors.contentSurface)
            .cornerRadius(20)
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
struct ChartData: Identifiable {
    let id = UUID()
    let hour: String
    let traffic: Int
}

#Preview {
    LiveView()
        .preferredColorScheme(nil)
}
