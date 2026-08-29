import Foundation

struct DailyMetricSample: Identifiable {
    let date: Date
    let value: Double

    var id: Date { date }
}

enum MetricDataQuality {
    static let maximumPlausibleDailyActiveCalories = 6_000.0

    static func plausibleDailyActiveCalories(_ samples: [DailyMetricSample]) -> [DailyMetricSample] {
        samples.filter { sample in
            sample.value > 0 && sample.value <= maximumPlausibleDailyActiveCalories
        }
    }
}
