import SwiftUI

struct SleepHRActivityView: View {
    let sessions: [SleepSession]
    let sleepHeartRates: [Date: Double]
    let dailyCalories: [DailyMetricSample]

    private struct Point: Identifiable {
        let date: Date
        let calories: Double
        let sleepHR: Double

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
                  let hr = sleepHeartRates[session.nightDate],
                  cals > 0 else { return nil }
            return Point(date: session.nightDate, calories: cals, sleepHR: hr)
        }
    }

    var body: some View {
        let chartPoints = points

        VStack(alignment: .leading, spacing: 8) {
            Text("Avg Sleep Heart Rate vs Activity")
                .font(.headline)
            Text("Active calories on day N vs average heart rate during sleep that night")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if chartPoints.isEmpty {
                Text("No paired heart rate and activity data available — requires Apple Watch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                MetricScatterChartView(
                    title: "Active Calories vs Sleep HR",
                    points: chartPoints.map { (x: $0.calories, y: $0.sleepHR) },
                    color: .orange,
                    xAxisLabel: "Active Calories",
                    yAxisLabel: "Sleep HR (bpm)",
                    interpretation: { slope in
                        slope <= 0
                            ? "more activity → lower sleep HR"
                            : "more activity → higher sleep HR"
                    }
                )
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
