import Foundation
import Testing
@testable import somnus

struct AwakeEventTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test func awakeEventWithEnoughStepsIsLikelyOutOfBed() {
        let start = date("2026-05-01 22:00")
        let session = SleepSession(
            nightDate: calendar.startOfDay(for: start.addingTimeInterval(9 * 3600)),
            stages: [
                SleepStage(startDate: start, endDate: start.addingTimeInterval(2 * 3600), type: .core),
                SleepStage(startDate: start.addingTimeInterval(2 * 3600), endDate: start.addingTimeInterval(2.2 * 3600), type: .awake),
                SleepStage(startDate: start.addingTimeInterval(2.2 * 3600), endDate: start.addingTimeInterval(7 * 3600), type: .rem),
            ],
            movementSamples: [
                MovementSample(
                    startDate: start.addingTimeInterval(2 * 3600 + 60),
                    endDate: start.addingTimeInterval(2 * 3600 + 180),
                    stepCount: 18,
                    distance: 12
                )
            ]
        )

        #expect(session.awakeEvents.count == 1)
        #expect(session.awakeEvents.first?.classification == .likelyOutOfBed)
        #expect(session.movementConfirmedAwakeningCount == 1)
        #expect(session.likelyOutOfBedDuration == 12 * 60)
    }

    @Test func derivedAwakeEventIdentityIsStableAcrossRecomputation() throws {
        let start = date("2026-05-01 22:00")
        let session = SleepSession(
            nightDate: calendar.startOfDay(for: start.addingTimeInterval(9 * 3600)),
            stages: [
                SleepStage(startDate: start, endDate: start.addingTimeInterval(2 * 3600), type: .core),
                SleepStage(startDate: start.addingTimeInterval(2 * 3600), endDate: start.addingTimeInterval(2.2 * 3600), type: .awake),
                SleepStage(startDate: start.addingTimeInterval(2.2 * 3600), endDate: start.addingTimeInterval(7 * 3600), type: .rem),
            ],
            movementSamples: [
                MovementSample(
                    startDate: start.addingTimeInterval(2 * 3600 + 60),
                    endDate: start.addingTimeInterval(2 * 3600 + 180),
                    stepCount: 18,
                    distance: 12
                )
            ]
        )

        let first = try #require(session.awakeEvents.first)
        let second = try #require(session.awakeEvents.first)

        #expect(first.id == second.id)
    }

    @Test func movementSampleIdentityIsDerivedFromSampleContent() {
        let start = date("2026-05-01 22:00")
        let first = MovementSample(
            startDate: start,
            endDate: start.addingTimeInterval(60),
            stepCount: 4,
            distance: 2,
            standHourCount: 1,
            sourceName: "Watch"
        )
        let second = MovementSample(
            startDate: start,
            endDate: start.addingTimeInterval(60),
            stepCount: 4,
            distance: 2,
            standHourCount: 1,
            sourceName: "Watch"
        )

        #expect(first.id == second.id)
    }

    @Test func awakeEventWithoutMovementStaysRestlessInBed() {
        let start = date("2026-05-01 22:00")
        let session = SleepSession(
            nightDate: calendar.startOfDay(for: start.addingTimeInterval(9 * 3600)),
            stages: [
                SleepStage(startDate: start, endDate: start.addingTimeInterval(2 * 3600), type: .core),
                SleepStage(startDate: start.addingTimeInterval(2 * 3600), endDate: start.addingTimeInterval(2.05 * 3600), type: .awake),
                SleepStage(startDate: start.addingTimeInterval(2.05 * 3600), endDate: start.addingTimeInterval(7 * 3600), type: .deep),
            ]
        )

        #expect(session.awakeEvents.count == 1)
        #expect(session.awakeEvents.first?.classification == .restlessInBed)
        #expect(session.movementConfirmedAwakeningCount == 0)
        #expect(session.likelyOutOfBedDuration == 0)
    }

    @Test func awakeEventWithStandHourEvidenceIsLikelyOutOfBed() {
        let start = date("2026-05-01 22:00")
        let session = SleepSession(
            nightDate: calendar.startOfDay(for: start.addingTimeInterval(9 * 3600)),
            stages: [
                SleepStage(startDate: start, endDate: start.addingTimeInterval(2 * 3600), type: .core),
                SleepStage(startDate: start.addingTimeInterval(2 * 3600), endDate: start.addingTimeInterval(2.05 * 3600), type: .awake),
                SleepStage(startDate: start.addingTimeInterval(2.05 * 3600), endDate: start.addingTimeInterval(7 * 3600), type: .deep),
            ],
            movementSamples: [
                MovementSample(
                    startDate: start.addingTimeInterval(2 * 3600),
                    endDate: start.addingTimeInterval(3 * 3600),
                    standHourCount: 1
                )
            ]
        )

        #expect(session.awakeEvents.count == 1)
        #expect(session.awakeEvents.first?.classification == .likelyOutOfBed)
        #expect(session.movementConfirmedAwakeningCount == 1)
    }

    @Test func standHourWithinSleepWindowCreatesInferredOutOfBedEvent() throws {
        let start = date("2026-05-01 22:00")
        let session = SleepSession(
            nightDate: calendar.startOfDay(for: start.addingTimeInterval(9 * 3600)),
            stages: [
                SleepStage(startDate: start, endDate: start.addingTimeInterval(7 * 3600), type: .core),
            ],
            movementSamples: [
                MovementSample(
                    startDate: start.addingTimeInterval(3 * 3600),
                    endDate: start.addingTimeInterval(4 * 3600),
                    standHourCount: 1
                )
            ]
        )

        let event = try #require(session.awakeEvents.first)

        #expect(session.awakeEvents.count == 1)
        #expect(event.classification == .likelyOutOfBed)
        #expect(event.duration == 10 * 60)
        #expect(session.movementConfirmedAwakeningCount == 1)
    }

    @Test func trendSummaryTracksMovementConfirmedWakeups() {
        let start = date("2026-05-01 22:00")
        let sessions = (0..<3).map { offset in
            let dayStart = calendar.date(byAdding: .day, value: offset, to: start)!
            return SleepSession(
                nightDate: calendar.startOfDay(for: dayStart.addingTimeInterval(9 * 3600)),
                stages: [
                    SleepStage(startDate: dayStart, endDate: dayStart.addingTimeInterval(2 * 3600), type: .core),
                    SleepStage(startDate: dayStart.addingTimeInterval(2 * 3600), endDate: dayStart.addingTimeInterval(2.1 * 3600), type: .awake),
                    SleepStage(startDate: dayStart.addingTimeInterval(2.1 * 3600), endDate: dayStart.addingTimeInterval(7 * 3600), type: .deep),
                ],
                movementSamples: offset == 1 ? [
                    MovementSample(
                        startDate: dayStart.addingTimeInterval(2 * 3600 + 30),
                        endDate: dayStart.addingTimeInterval(2 * 3600 + 90),
                        stepCount: 10
                    )
                ] : []
            )
        }

        let summary = SleepTrendSummary(sessions: sessions, targetSleep: 8 * 3600)

        #expect(summary.totalMovementConfirmedWakeups == 1)
        #expect(summary.totalLikelyOutOfBedDuration == 6 * 60)
    }

    @Test func movementQueryWindowsOnlyCoverAwakeIntervals() {
        let start = date("2026-05-01 22:00")
        let session = SleepSession(
            nightDate: calendar.startOfDay(for: start.addingTimeInterval(9 * 3600)),
            stages: [
                SleepStage(startDate: start, endDate: start.addingTimeInterval(2 * 3600), type: .core),
                SleepStage(startDate: start.addingTimeInterval(2 * 3600), endDate: start.addingTimeInterval(2.1 * 3600), type: .awake),
                SleepStage(startDate: start.addingTimeInterval(2.1 * 3600), endDate: start.addingTimeInterval(7 * 3600), type: .deep),
            ]
        )

        let windows = AwakeEventDetector.movementEvidenceWindows(for: session)

        #expect(windows.count == 1)
        #expect(windows[0].start == start.addingTimeInterval(2 * 3600 - 2 * 60))
        #expect(windows[0].end == start.addingTimeInterval(2.1 * 3600 + 5 * 60))
        #expect(windows[0].end.timeIntervalSince(windows[0].start) < 15 * 60)
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }
}
