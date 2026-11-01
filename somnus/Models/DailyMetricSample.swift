import Foundation

nonisolated struct DailyMetricSample: Identifiable, Sendable {
    let date: Date
    let value: Double

    var id: Date { date }
}

nonisolated enum MetricDataQuality {
    static let maximumPlausibleDailyActiveCalories = 6_000.0

    static func plausibleDailyActiveCalories(_ samples: [DailyMetricSample]) -> [DailyMetricSample] {
        samples.filter { sample in
            sample.value > 0 && sample.value <= maximumPlausibleDailyActiveCalories
        }
    }
}
