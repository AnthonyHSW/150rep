import SwiftUI
import Charts

struct LiveView: View {
    @State private var currentCrowding = 6
    @State private var selectedReport: Int? = nil
    @State private var reportSubmitted = false
    @State private var reportConfirmationShown = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Live Busyness Meter
                    BusynessMeterSection(currentCrowding: currentCrowding)

                    // Best Time Today
                    DailyTrafficChartSection()

                    // Quick Crowd Report
                    CrowdReportSection(
                        selectedReport: $selectedReport,
                        onSubmit: handleReportSubmit
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.hidden)
            .background(AppColors.pageBackground)
            .navigationTitle("ARC right now")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("View Options", action: {})
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.headline)
                    }
                }
            }
            .alert("Thank You", isPresented: $reportConfirmationShown) {
                Button("OK") { }
            } message: {
                Text("Thanks—you're helping other Anteaters plan.")
            }
        }
    }

    private func handleReportSubmit(_ level: Int) {
        selectedReport = level
        reportConfirmationShown = true
    }
}

// MARK: - Busyness Meter Section
struct BusynessMeterSection: View {
    let currentCrowding: Int

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Text("\(currentCrowding)/10 · \(AppColors.crowdingLabel(for: currentCrowding))")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)

                BusynessMeterGauge(value: Double(currentCrowding), maxValue: 10)
                    .frame(height: 140)

                VStack(spacing: 4) {
                    Text("~3–5 min")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Estimated equipment wait")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(20)
            .background(AppColors.contentSurface)
            .cornerRadius(20)

            Text("Updated 2 min ago · 18 recent reports")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - Busyness Meter Gauge
struct BusynessMeterGauge: View {
    let value: Double
    let maxValue: Double

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .trim(from: 0, to: 0.5)
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
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(180))

            // Progress indicator
            Circle()
                .trim(from: 0, to: min(value / maxValue * 0.5, 0.5))
                .stroke(
                    AppColors.crowdingColor(for: Int(value)),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(180))

            // Marker
            let angle = (value / maxValue) * 180
            VStack {
                Circle()
                    .fill(AppColors.crowdingColor(for: Int(value)))
                    .frame(width: 14, height: 14)
                    .shadow(radius: 2)
                Spacer()
            }
            .rotationEffect(.degrees(angle - 90))
            .padding(8)

            // Labels
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("1")
                        .font(.caption2.weight(.semibold))
                    Text("Quiet")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("10")
                        .font(.caption2.weight(.semibold))
                    Text("Packed")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
        }
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
        VStack(alignment: .leading, spacing: 12) {
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

                    Spacer()

                    Label("Now", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Here now? How busy is it?")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            VStack(spacing: 12) {
                ForEach(reports, id: \.label) { report in
                    Button(action: {
                        onSubmit(report.level)
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .opacity(selectedReport == report.level ? 1 : 0)

                            Text(report.label)
                                .font(.system(size: 16, weight: .semibold))

                            Spacer()

                            Image(systemName: AppColors.crowdingColor(for: report.level) == AppColors.quiet ? "circle.fill" : "circle.fill")
                                .foregroundColor(AppColors.crowdingColor(for: report.level))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(
                            selectedReport == report.level
                                ? AppColors.crowdingColor(for: report.level).opacity(0.1)
                                : Color.clear
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    selectedReport == report.level
                                        ? AppColors.crowdingColor(for: report.level)
                                        : Color.gray.opacity(0.3),
                                    lineWidth: 2
                                )
                        )
                        .cornerRadius(12)
                        .foregroundColor(.primary)
                    }
                }
            }
        }
        .padding(.bottom, 40)
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
