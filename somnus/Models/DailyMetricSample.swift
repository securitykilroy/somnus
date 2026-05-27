import Foundation

struct DailyMetricSample: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}
