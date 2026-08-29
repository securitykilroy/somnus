import Foundation
import Testing
@testable import somnus

struct SleepLatencyAnalysisTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test func validIntentBeforeFirstSleepCreatesLatencyRecord() throws {
        let firstSleep = date("2026-05-03 23:15")
        let session = sleepSession(firstSleep: firstSleep)
        let event = SleepIntentEvent(
            id: UUID(),
            timestamp: firstSleep.addingTimeInterval(-35 * 60),
            kind: .tryingToSleep,
            note: nil,
            createdAt: firstSleep,
            updatedAt: firstSleep
        )

        let records = SleepLatencyAnalyzer.records(
            sessions: [session],
            events: [event],
            calendar: calendar
        )

        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.intentEventID == event.id)
        #expect(record.sessionID == session.id)
        #expect(record.latency == 35 * 60)
        #expect(record.appleLatency == session.sleepLatency)
    }

    @Test func matchingUsesMostRecentValidTryingToSleepEvent() throws {
        let firstSleep = date("2026-05-03 23:15")
        let session = sleepSession(firstSleep: firstSleep)
        let older = intent(at: firstSleep.addingTimeInterval(-2 * 3600))
        let newer = intent(at: firstSleep.addingTimeInterval(-20 * 60))

        let records = SleepLatencyAnalyzer.records(
            sessions: [session],
            events: [older, newer],
            calendar: calendar
        )

        let record = try #require(records.first)
        #expect(record.intentEventID == newer.id)
        #expect(record.latency == 20 * 60)
    }

    @Test func matchingIgnoresMissingAfterSleepAndTooOldEvents() {
        let firstSleep = date("2026-05-03 23:15")
        let session = sleepSession(firstSleep: firstSleep)
        let awake = SleepIntentEvent(
            id: UUID(),
            timestamp: firstSleep.addingTimeInterval(-30 * 60),
            kind: .awake,
            note: nil,
            createdAt: firstSleep,
            updatedAt: firstSleep
        )
        let afterSleep = intent(at: firstSleep.addingTimeInterval(60))
        let tooOld = intent(at: firstSleep.addingTimeInterval(-7 * 3600))

        #expect(SleepLatencyAnalyzer.records(sessions: [session], events: [], calendar: calendar).isEmpty)
        #expect(SleepLatencyAnalyzer.records(sessions: [session], events: [awake], calendar: calendar).isEmpty)
        #expect(SleepLatencyAnalyzer.records(sessions: [session], events: [afterSleep], calendar: calendar).isEmpty)
        #expect(SleepLatencyAnalyzer.records(sessions: [session], events: [tooOld], calendar: calendar).isEmpty)
    }

    @Test func summaryCalculatesRecentAveragesAndOutliers() throws {
        let sessions = (0..<8).map { offset in
            let firstSleep = date("2026-05-\(String(format: "%02d", 3 + offset)) 23:00")
            return sleepSession(firstSleep: firstSleep)
        }
        let latencies: [TimeInterval] = [10, 12, 11, 13, 12, 15, 14, 120].map { $0 * 60 }
        let events = zip(sessions, latencies).map { session, latency in
            intent(at: session.normalizedTimeline.firstSleepStart!.addingTimeInterval(-latency))
        }

        let records = SleepLatencyAnalyzer.records(
            sessions: sessions,
            events: events,
            calendar: calendar
        )
        let summary = SleepLatencyAnalyzer.summary(records: records, calendar: calendar)

        #expect(summary.count == 8)
        #expect(summary.latestLatency == 120.0 * 60)
        #expect(summary.sevenDayAverage == Double(12 + 11 + 13 + 12 + 15 + 14 + 120) * 60 / 7)
        #expect(summary.thirtyDayAverage == latencies.reduce(0, +) / Double(latencies.count))
        #expect(summary.medianLatency == 12.5 * 60)
        #expect(summary.longestRecent?.latency == 120.0 * 60)
        #expect(summary.longLatencyCount == 1)
        #expect(summary.veryLongLatencyCount == 1)
        let outlier = try #require(summary.outliers.first)
        #expect(outlier.record.latency == 120 * 60)
    }

    @Test func summaryTracksAppleLatencyMismatch() throws {
        let firstSleep = date("2026-05-03 23:15")
        let session = sleepSession(firstSleep: firstSleep)
        let event = intent(at: firstSleep.addingTimeInterval(-65 * 60))

        let record = try #require(SleepLatencyAnalyzer.records(
            sessions: [session],
            events: [event],
            calendar: calendar
        ).first)
        let summary = SleepLatencyAnalyzer.summary(records: [record], calendar: calendar)

        #expect(record.latencyBand == .long)
        #expect(record.hasAppleLatencyMismatch)
        #expect(record.appleLatencyDelta == 50 * 60)
        #expect(summary.appleMismatchCount == 1)
        #expect(try #require(summary.averageAppleLatencyDelta) == 50 * 60)
    }

    private func sleepSession(firstSleep: Date) -> SleepSession {
        let bedStart = firstSleep.addingTimeInterval(-15 * 60)
        return SleepSession(
            nightDate: calendar.startOfDay(for: firstSleep.addingTimeInterval(7 * 3600)),
            stages: [
                SleepStage(startDate: bedStart, endDate: firstSleep, type: .inBed),
                SleepStage(startDate: firstSleep, endDate: firstSleep.addingTimeInterval(7 * 3600), type: .core),
            ]
        )
    }

    private func intent(at timestamp: Date) -> SleepIntentEvent {
        SleepIntentEvent(
            id: UUID(),
            timestamp: timestamp,
            kind: .tryingToSleep,
            note: nil,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }
}
