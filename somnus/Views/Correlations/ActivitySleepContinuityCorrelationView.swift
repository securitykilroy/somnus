import SwiftUI

struct ActivitySleepContinuityCorrelationView: View {
    let sessions: [SleepSession]
    let dailyCalories: [DailyMetricSample]

    struct Point: Identifiable {
        let date: Date
        let calories: Double
        let wasoMinutes: Double

        var id: Date { date }
    }

    static func points(
        sessions: [SleepSession],
        dailyCalories: [DailyMetricSample],
        calendar: Calendar = .current
    ) -> [Point] {
        let calsByDay = Dictionary(
            dailyCalories.map { (calendar.startOfDay(for: $0.date), $0.value) },
            uniquingKeysWith: { $1 }
        )
        return sessions.compactMap { session in
            let activityDay = calendar.date(byAdding: .day, value: -1, to: session.nightDate)!
            let wasoMinutes = session.wakeAfterSleepOnset / 60
            guard let cals = calsByDay[calendar.startOfDay(for: activityDay)],
                  cals > 0 else { return nil }
            return Point(
                date: session.nightDate,
                calories: cals,
                wasoMinutes: wasoMinutes
            )
        }
    }

    private var points: [Point] {
        Self.points(sessions: sessions, dailyCalories: dailyCalories)
    }

    var body: some View {
        let chartPoints = points

        VStack(alignment: .leading, spacing: 8) {
            Text("Activity vs Sleep Continuity")
                .font(.headline)
            Text("Active calories on day N vs awake time after sleep onset that night")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if chartPoints.isEmpty {
                Text("No paired activity and wake-after-sleep data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                MetricScatterChartView(
                    title: "Active Calories vs WASO",
                    points: chartPoints.map { (x: $0.calories, y: $0.wasoMinutes) },
                    color: .orange,
                    xAxisLabel: "Active Calories",
                    yAxisLabel: "WASO (min)",
                    interpretation: { slope in
                        slope >= 0
                            ? "more activity → more wake after sleep onset"
                            : "more activity → less wake after sleep onset"
                    }
                )
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
