import Foundation
import Testing
@testable import somnus

struct SleepAnalysisTests {
    private let calendar = Calendar(identifier: .gregorian)

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
        #expect(session.fragmentationIndex > 0.3)
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
