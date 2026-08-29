import SwiftUI

struct ActivitySleepCorrelationView: View {
    let sessions: [SleepSession]
    let dailyCalories: [DailyMetricSample]

    private struct Point: Identifiable {
        let date: Date
        let calories: Double
        let sleepHours: Double

        var id: Date { date }
    }

    private var points: [Point] {
        let calsByDay = Dictionary(
            dailyCalories.map { (Calendar.current.startOfDay(for: $0.date), $0.value) },
            uniquingKeysWith: { $1 }
        )
        return sessions.compactMap { session in
            let activityDay = Calendar.current.date(byAdding: .day, value: -1, to: session.nightDate)!
            guard let cals = calsByDay[Calendar.current.startOfDay(for: activityDay)],
                  cals > 0 else { return nil }
            return Point(date: session.nightDate, calories: cals, sleepHours: session.totalSleep.asHours)
        }
    }

    var body: some View {
        let chartPoints = points

        VStack(alignment: .leading, spacing: 8) {
            Text("Activity vs Next Night's Sleep")
                .font(.headline)
            Text("Active calories on day N vs sleep duration on night N")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if chartPoints.isEmpty {
                Text("No paired activity and sleep data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                MetricScatterChartView(
                    title: "Active Calories vs Sleep Duration",
                    points: chartPoints.map { (x: $0.calories, y: $0.sleepHours) },
                    color: .blue,
                    xAxisLabel: "Active Calories",
                    yAxisLabel: "Sleep (h)",
                    interpretation: { slope in
                        slope >= 0 ? "more activity → more sleep" : "more activity → less sleep"
                    }
                )
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
