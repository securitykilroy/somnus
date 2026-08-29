import SwiftUI

/// The payoff for logging meals: how the gap between the last meal and sleep
/// onset lines up against the night that followed.
struct MealTimingSleepView: View {
    let sessions: [SleepSession]
    let meals: [MealEvent]

    private var records: [MealSleepRecord] {
        MealSleepAnalyzer.records(sessions: sessions, meals: meals)
    }

    var body: some View {
        let records = self.records
        let summary = MealSleepAnalyzer.summary(records: records)

        VStack(alignment: .leading, spacing: 8) {
            Text("Meal Timing vs Sleep")
                .font(.headline)
            Text("Hours between your last logged meal and falling asleep, against that night's sleep")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if records.isEmpty {
                Text("No nights yet with a meal logged beforehand — log meals from the widget or by asking Siri.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                if summary.hasComparison {
                    comparison(summary)
                }

                MetricScatterChartView(
                    title: "Sleep Efficiency",
                    points: records.map { (x: $0.gapHours, y: $0.efficiency * 100) },
                    color: .teal,
                    xAxisLabel: "Hours Since Last Meal",
                    yAxisLabel: "Efficiency %",
                    interpretation: { $0 >= 0 ? "eating earlier → more efficient sleep" : "eating earlier → less efficient sleep" }
                )

                MetricScatterChartView(
                    title: "Deep Sleep %",
                    points: records.map { (x: $0.gapHours, y: $0.deepRatio * 100) },
                    color: .indigo,
                    xAxisLabel: "Hours Since Last Meal",
                    yAxisLabel: "Deep %",
                    interpretation: { $0 >= 0 ? "eating earlier → more deep sleep" : "eating earlier → less deep sleep" }
                )

                MetricScatterChartView(
                    title: "Time Awake in Bed",
                    points: records.map { (x: $0.gapHours, y: $0.awakeDuration / 60) },
                    color: .orange,
                    xAxisLabel: "Hours Since Last Meal",
                    yAxisLabel: "Awake (min)",
                    interpretation: { $0 >= 0 ? "eating earlier → more time awake" : "eating earlier → less time awake" }
                )

                Text("\(records.count) night\(records.count == 1 ? "" : "s") paired" +
                     (summary.medianGap.map { " · median gap \($0.hoursAndMinutes)" } ?? ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Shown alongside the scatters because a handful of nights is rarely
    /// enough for a regression line to mean anything, but the two group
    /// averages still tell you something.
    @ViewBuilder
    private func comparison(_ summary: MealSleepSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Late meals vs early meals")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                column(
                    title: "Within \(Int(summary.thresholdHours))h of sleep",
                    nights: summary.lateNights.count,
                    efficiency: summary.lateEfficiency,
                    deepRatio: summary.lateDeepRatio,
                    totalSleep: summary.lateTotalSleep,
                    tint: .orange
                )
                Divider()
                column(
                    title: "More than \(Int(summary.thresholdHours))h before",
                    nights: summary.earlyNights.count,
                    efficiency: summary.earlyEfficiency,
                    deepRatio: summary.earlyDeepRatio,
                    totalSleep: summary.earlyTotalSleep,
                    tint: .teal
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func column(
        title: String,
        nights: Int,
        efficiency: Double,
        deepRatio: Double,
        totalSleep: TimeInterval,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(nights) night\(nights == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(totalSleep.hoursAndMinutes)
                .font(.system(.title3, design: .rounded, weight: .semibold))
            Text("\(Int(efficiency * 100))% efficiency · \(Int(deepRatio * 100))% deep")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
