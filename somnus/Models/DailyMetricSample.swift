import Foundation

struct DailyMetricSample: Identifiable {
    let date: Date
    let value: Double

    var id: Date { date }
}
