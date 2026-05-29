import SwiftUI
import Charts

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

    private func regression(for points: [Point]) -> (slope: Double, intercept: Double)? {
        guard points.count >= 3 else { return nil }
        let n = Double(points.count)
        let xs = points.map(\.calories)
        let ys = points.map(\.wasoMinutes)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
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
                let xMin = chartPoints.map(\.calories).min()!
                let xMax = chartPoints.map(\.calories).max()!

                Chart {
                    ForEach(chartPoints) { pt in
                        PointMark(
                            x: .value("Calories", pt.calories),
                            y: .value("WASO (min)", pt.wasoMinutes)
                        )
                        .foregroundStyle(Color.orange.opacity(0.75))
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
                                y: .value("WASO (min)", pt.y)
                            )
                            .foregroundStyle(Color.orange.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5]))
                        }
                    }
                }
                .chartXAxisLabel("Active Calories")
                .chartYAxisLabel("WASO (min)")
                .frame(height: 220)

                if let reg = regression {
                    let direction = reg.slope >= 0
                        ? "more activity -> more wake after sleep onset"
                        : "more activity -> less wake after sleep onset"
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
