import Foundation
import Testing
@testable import somnus

struct DailyMetricSampleTests {
    @Test func plausibleDailyActiveCaloriesDropsUnrealisticOutliers() {
        let calendar = Calendar(identifier: .gregorian)
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 2))!
        let day3 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 3))!

        let filtered = MetricDataQuality.plausibleDailyActiveCalories([
            DailyMetricSample(date: day1, value: 650),
            DailyMetricSample(date: day2, value: 6_000),
            DailyMetricSample(date: day3, value: 15_000),
        ])

        #expect(filtered.map(\.value) == [650, 6_000])
    }

    @Test func plausibleDailyActiveCaloriesDropsZeroAndNegativeValues() {
        let calendar = Calendar(identifier: .gregorian)
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 2))!
        let day3 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 3))!

        let filtered = MetricDataQuality.plausibleDailyActiveCalories([
            DailyMetricSample(date: day1, value: -20),
            DailyMetricSample(date: day2, value: 0),
            DailyMetricSample(date: day3, value: 500),
        ])

        #expect(filtered.map(\.value) == [500])
    }
}
