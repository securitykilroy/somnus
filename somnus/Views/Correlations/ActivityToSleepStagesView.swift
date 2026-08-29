import SwiftUI

struct ActivityToSleepStagesView: View {
    let sessions: [SleepSession]
    let dailyCalories: [DailyMetricSample]

    private struct Pairing {
        let calories: Double
        let session: SleepSession
    }

    private var pairings: [Pairing] {
        let calsByDay = Dictionary(
            dailyCalories.map { (Calendar.current.startOfDay(for: $0.date), $0.value) },
            uniquingKeysWith: { $1 }
        )
        return sessions.compactMap { session in
            let activityDay = Calendar.current.date(byAdding: .day, value: -1, to: session.nightDate)!
            guard let cals = calsByDay[Calendar.current.startOfDay(for: activityDay)],
                  cals > 0 else { return nil }
            return Pairing(calories: cals, session: session)
        }
    }

    var body: some View {
        let pairs = pairings

        VStack(alignment: .leading, spacing: 8) {
            Text("Activity vs Sleep Stage Composition")
                .font(.headline)
            Text("Active calories on day N vs stage makeup of sleep that night")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if pairs.isEmpty {
                Text("No paired activity and sleep data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                MetricScatterChartView(
                    title: "Deep Sleep %",
                    points: pairs.map { (x: $0.calories, y: $0.session.deepRatio * 100) },
                    color: .indigo,
                    xAxisLabel: "Active Calories",
                    yAxisLabel: "Deep %",
                    interpretation: { $0 >= 0 ? "more activity → more deep sleep" : "more activity → less deep sleep" }
                )

                MetricScatterChartView(
                    title: "REM Sleep %",
                    points: pairs.map { (x: $0.calories, y: $0.session.remRatio * 100) },
                    color: .teal,
                    xAxisLabel: "Active Calories",
                    yAxisLabel: "REM %",
                    interpretation: { $0 >= 0 ? "more activity → more REM sleep" : "more activity → less REM sleep" }
                )

                MetricScatterChartView(
                    title: "Fragmentation",
                    points: pairs.map { (x: $0.calories, y: $0.session.fragmentationIndex) },
                    color: .orange,
                    xAxisLabel: "Active Calories",
                    yAxisLabel: "Fragmentation",
                    interpretation: { $0 >= 0 ? "more activity → more fragmented sleep" : "more activity → less fragmented sleep" }
                )
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
