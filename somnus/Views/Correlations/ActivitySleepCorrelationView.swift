import SwiftUI
import Charts

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

    private func regression(for points: [Point]) -> (slope: Double, intercept: Double)? {
        guard points.count >= 3 else { return nil }
        let n = Double(points.count)
        let xs = points.map(\.calories), ys = points.map(\.sleepHours)
        let sumX = xs.reduce(0, +), sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = xs.reduce(0) { $0 + $1 * $1 }
        let denom = n * sumX2 - sumX * sumX
        guard abs(denom) > 1e-10 else { return nil }
        let slope = (n * sumXY - sumX * sumY) / denom
        return (slope, (sumY - slope * sumX) / n)
    }

    var body: some View {
        let chartPoints = points
        let regression = regression(for: chartPoints)

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
                let xMin = chartPoints.map(\.calories).min()!
                let xMax = chartPoints.map(\.calories).max()!

                Chart {
                    ForEach(chartPoints) { pt in
                        PointMark(
                            x: .value("Calories", pt.calories),
                            y: .value("Sleep (h)", pt.sleepHours)
                        )
                        .foregroundStyle(Color.blue.opacity(0.7))
                        .symbolSize(40)
                    }

                    if let reg = regression {
                        let linePoints = [
                            (x: xMin, y: reg.slope * xMin + reg.intercept),
                            (x: xMax, y: reg.slope * xMax + reg.intercept),
                        ]
                        ForEach(Array(linePoints.enumerated()), id: \.offset) { _, pt in
                            LineMark(
                                x: .value("Calories", pt.x),
                                y: .value("Sleep (h)", pt.y)
                            )
                            .foregroundStyle(Color.blue.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5]))
                        }
                    }

                    RuleMark(y: .value("8h", 8.0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.red.opacity(0.4))
                }
                .chartXAxisLabel("Active Calories")
                .chartYAxisLabel("Sleep (h)")
                .frame(height: 220)

                if let reg = regression {
                    let direction = reg.slope >= 0 ? "more activity → more sleep" : "more activity → less sleep"
                    Text(direction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
