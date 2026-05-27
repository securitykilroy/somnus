import SwiftUI
import Charts

struct SleepHRActivityView: View {
    let sessions: [SleepSession]
    let sleepHeartRates: [Date: Double]
    let dailyCalories: [DailyMetricSample]

    private struct Point: Identifiable {
        let id = UUID()
        let calories: Double
        let sleepHR: Double
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
            return Point(calories: cals, sleepHR: hr)
        }
    }

    private var regression: (slope: Double, intercept: Double)? {
        guard points.count >= 3 else { return nil }
        let n = Double(points.count)
        let xs = points.map(\.calories), ys = points.map(\.sleepHR)
        let sumX = xs.reduce(0, +), sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = xs.reduce(0) { $0 + $1 * $1 }
        let denom = n * sumX2 - sumX * sumX
        guard abs(denom) > 1e-10 else { return nil }
        let slope = (n * sumXY - sumX * sumY) / denom
        return (slope, (sumY - slope * sumX) / n)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Avg Sleep Heart Rate vs Activity")
                .font(.headline)
            Text("Active calories on day N vs average heart rate during sleep that night")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if points.isEmpty {
                Text("No paired heart rate and activity data available — requires Apple Watch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                let xMin = points.map(\.calories).min()!
                let xMax = points.map(\.calories).max()!

                Chart {
                    ForEach(points) { pt in
                        PointMark(
                            x: .value("Calories", pt.calories),
                            y: .value("Sleep HR (bpm)", pt.sleepHR)
                        )
                        .foregroundStyle(Color.orange.opacity(0.7))
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
                                y: .value("Sleep HR (bpm)", pt.y)
                            )
                            .foregroundStyle(Color.orange.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5]))
                        }
                    }
                }
                .chartXAxisLabel("Active Calories")
                .chartYAxisLabel("bpm")
                .frame(height: 220)

                if let reg = regression {
                    let direction = reg.slope <= 0
                        ? "more activity → lower sleep HR (recovery response)"
                        : "more activity → higher sleep HR"
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
