import Foundation
import Testing
@testable import somnus

struct SleepAnalysisTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test func normalizerPreservesRawSamplesAndResolvesOverlaps() {
        let start = date("2026-05-01 22:00")
        let samples = [
            SleepStage(startDate: start, endDate: start.addingTimeInterval(2 * 3600), type: .core, sourceName: "Watch"),
            SleepStage(startDate: start.addingTimeInterval(3600), endDate: start.addingTimeInterval(3 * 3600), type: .deep, sourceName: "Phone"),
        ]

        let normalized = SleepTimelineNormalizer.normalize(samples)

        #expect(normalized.rawStages.count == 2)
        #expect(normalized.segments.count == 3)
        #expect(normalized.segments.map(\.type) == [.core, .deep, .deep])
        #expect(normalized.totalOverlap == 3600)
        #expect(normalized.duration(for: .core) == 3600)
        #expect(normalized.duration(for: .deep) == 7200)
    }

    @Test func unspecifiedSleepCountsAsSleepButNotCoreSleep() {
        let start = date("2026-05-01 23:00")
        let session = SleepSession(
            nightDate: calendar.startOfDay(for: start.addingTimeInterval(8 * 3600)),
            stages: [
                SleepStage(startDate: start, endDate: start.addingTimeInterval(3600), type: .asleepUnspecified),
                SleepStage(startDate: start.addingTimeInterval(3600), endDate: start.addingTimeInterval(3 * 3600), type: .core),
            ]
        )

        #expect(session.totalSleep == 3 * 3600)
        #expect(session.coreDuration == 2 * 3600)
        #expect(session.unspecifiedSleepDuration == 3600)
        #expect(session.dataQuality.unknownSleepRatio == 1.0 / 3.0)
    }

    @Test func sleepMetricsIncludeLatencyWasoAndFragmentation() {
        let start = date("2026-05-01 22:00")
        let session = SleepSession(
            nightDate: calendar.startOfDay(for: start.addingTimeInterval(9 * 3600)),
            stages: [
                SleepStage(startDate: start, endDate: start.addingTimeInterval(20 * 60), type: .inBed),
                SleepStage(startDate: start.addingTimeInterval(20 * 60), endDate: start.addingTimeInterval(2 * 3600), type: .core),
                SleepStage(startDate: start.addingTimeInterval(2 * 3600), endDate: start.addingTimeInterval(2.25 * 3600), type: .awake),
                SleepStage(startDate: start.addingTimeInterval(2.25 * 3600), endDate: start.addingTimeInterval(5 * 3600), type: .deep),
                SleepStage(startDate: start.addingTimeInterval(5 * 3600), endDate: start.addingTimeInterval(5.25 * 3600), type: .awake),
                SleepStage(startDate: start.addingTimeInterval(5.25 * 3600), endDate: start.addingTimeInterval(7 * 3600), type: .rem),
            ]
        )

        #expect(session.sleepLatency == 20 * 60)
        #expect(session.wakeAfterSleepOnset == 30 * 60)
        #expect(session.awakeningCount == 2)
        #expect(session.longestSleepBlock == 2.75 * 3600)
        #expect(session.fragmentationIndex > 0.1)
    }

    @Test func trendSummaryCalculatesRollingBaselinesAndOutliers() {
        let start = date("2026-05-01 07:00")
        let sessions = (0..<10).map { offset in
            SleepSession(
                nightDate: calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: start))!,
                stages: [
                    SleepStage(
                        startDate: calendar.date(byAdding: .day, value: offset, to: start.addingTimeInterval(-8 * 3600))!,
                        endDate: calendar.date(byAdding: .day, value: offset, to: start.addingTimeInterval(offset == 8 ? -7 * 3600 : 0))!,
                        type: .core
                    )
                ]
            )
        }

        let summary = SleepTrendSummary(sessions: sessions, targetSleep: 8 * 3600)

        #expect(summary.sevenDayMean == 7 * 3600)
        #expect(summary.thirtyDayMean > 0)
        #expect(summary.outliers.count == 1)
        #expect(summary.outliers.first?.session.nightDate == sessions[8].nightDate)
    }

    @Test func trendOutlierIdentityIsStableAcrossRecomputation() throws {
        let start = date("2026-05-01 07:00")
        let sessions = (0..<10).map { offset in
            SleepSession(
                nightDate: calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: start))!,
                stages: [
                    SleepStage(
                        startDate: calendar.date(byAdding: .day, value: offset, to: start.addingTimeInterval(-8 * 3600))!,
                        endDate: calendar.date(byAdding: .day, value: offset, to: start.addingTimeInterval(offset == 8 ? -7 * 3600 : 0))!,
                        type: .core
                    )
                ]
            )
        }
        let summary = SleepTrendSummary(sessions: sessions, targetSleep: 8 * 3600)

        let first = try #require(summary.outliers.first)
        let second = try #require(summary.outliers.first)

        #expect(first.id == second.id)
    }

    @Test func dailyMetricSampleIdentityIsDerivedFromSampleDate() {
        let day = date("2026-05-01 00:00")
        let first = DailyMetricSample(date: day, value: 42)
        let second = DailyMetricSample(date: day, value: 42)

        #expect(first.id == second.id)
    }

    @Test func trendWindowFiltersRangeAgainstFixedEndDate() {
        let end = date("2026-05-27 12:00")
        let inside = SleepSession(
            nightDate: calendar.startOfDay(for: end.addingTimeInterval(-3 * 24 * 3600)),
            stages: [
                SleepStage(startDate: end.addingTimeInterval(-3 * 24 * 3600), endDate: end.addingTimeInterval(-3 * 24 * 3600 + 3600), type: .core)
            ]
        )
        let outside = SleepSession(
            nightDate: calendar.startOfDay(for: end.addingTimeInterval(-20 * 24 * 3600)),
            stages: [
                SleepStage(startDate: end.addingTimeInterval(-20 * 24 * 3600), endDate: end.addingTimeInterval(-20 * 24 * 3600 + 3600), type: .core)
            ]
        )

        let result = TrendWindow.sessions([outside, inside], range: .week, endingAt: end, calendar: calendar)

        #expect(result.map(\.id) == [inside.id])
    }

    @Test func trendWindowAppliesZoomAfterRangeFiltering() {
        let end = date("2026-05-27 12:00")
        let sessions = [40, 20, 5].map { daysAgo in
            let start = end.addingTimeInterval(TimeInterval(-daysAgo * 24 * 3600))
            return SleepSession(
                nightDate: calendar.startOfDay(for: start),
                stages: [
                    SleepStage(startDate: start, endDate: start.addingTimeInterval(3600), type: .core)
                ]
            )
        }

        let ranged = TrendWindow.sessions(sessions, range: .threeMonths, endingAt: end, calendar: calendar)
        let visible = TrendWindow.visibleSessions(ranged, zoom: .month, endingAt: end, calendar: calendar)

        #expect(visible.map(\.nightDate) == sessions.dropFirst().map(\.nightDate).sorted())
    }

    @Test func sleepHeartRateAveragesUsePrecomputedSessionWindows() {
        let firstStart = date("2026-05-01 22:00")
        let secondStart = date("2026-05-02 22:00")
        let sessions = [firstStart, secondStart].map { start in
            SleepSession(
                nightDate: calendar.startOfDay(for: start.addingTimeInterval(8 * 3600)),
                stages: [
                    SleepStage(startDate: start, endDate: start.addingTimeInterval(8 * 3600), type: .core)
                ]
            )
        }
        let samples = [
            HealthKitManager.TimedQuantitySample(startDate: firstStart.addingTimeInterval(-60), value: 50),
            HealthKitManager.TimedQuantitySample(startDate: firstStart.addingTimeInterval(60), value: 60),
            HealthKitManager.TimedQuantitySample(startDate: firstStart.addingTimeInterval(120), value: 80),
            HealthKitManager.TimedQuantitySample(startDate: firstStart.addingTimeInterval(8 * 3600), value: 200),
            HealthKitManager.TimedQuantitySample(startDate: secondStart.addingTimeInterval(60), value: 55),
            HealthKitManager.TimedQuantitySample(startDate: secondStart.addingTimeInterval(120), value: 65),
        ]

        let averages = HealthKitManager.averageSamplesBySession(samples: samples, sessions: sessions)

        #expect(averages[sessions[0].nightDate] == 70)
        #expect(averages[sessions[1].nightDate] == 60)
    }

    @Test func activityLatencyCorrelationPairsPreviousDayCaloriesWithSleepLatency() {
        let bedStart = date("2026-05-02 22:00")
        let session = SleepSession(
            nightDate: calendar.startOfDay(for: bedStart.addingTimeInterval(8 * 3600)),
            stages: [
                SleepStage(startDate: bedStart, endDate: bedStart.addingTimeInterval(30 * 60), type: .inBed),
                SleepStage(startDate: bedStart.addingTimeInterval(30 * 60), endDate: bedStart.addingTimeInterval(8 * 3600), type: .core),
            ]
        )
        let previousDay = calendar.startOfDay(for: bedStart)
        let calories = [
            DailyMetricSample(date: previousDay, value: 725),
            DailyMetricSample(date: calendar.date(byAdding: .day, value: -1, to: previousDay)!, value: 100),
        ]

        let points = ActivitySleepLatencyCorrelationView.points(
            sessions: [session],
            dailyCalories: calories,
            calendar: calendar
        )

        #expect(points.count == 1)
        #expect(points.first?.calories == 725)
        #expect(points.first?.latencyMinutes == 30)
    }

    @MainActor
    @Test func metricsFetchWindowDoesNotExpandPastOneYearForLongHistory() {
        let now = date("2026-05-27 12:00")
        let oldStart = date("2021-01-01 23:00")
        let session = SleepSession(
            nightDate: calendar.startOfDay(for: oldStart.addingTimeInterval(8 * 3600)),
            stages: [
                SleepStage(startDate: oldStart, endDate: oldStart.addingTimeInterval(8 * 3600), type: .core)
            ]
        )

        let window = SleepStore.metricsFetchWindow(for: [session], end: now, calendar: calendar)

        #expect(window.start == calendar.date(byAdding: .year, value: -1, to: now)!)
        #expect(window.end == now)
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }
}
