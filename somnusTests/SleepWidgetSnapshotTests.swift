import Foundation
import Testing
@testable import somnus

struct SleepWidgetSnapshotTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: string)!
    }

    /// 22:00 -> 06:00 with 1h deep, 1h REM, 30m awake, rest core.
    private func session(nightDate: Date) -> SleepSession {
        let start = date("2026-05-02 22:00")
        return SleepSession(
            nightDate: nightDate,
            stages: [
                SleepStage(startDate: start, endDate: start.addingTimeInterval(2 * 3600), type: .core),
                SleepStage(startDate: start.addingTimeInterval(2 * 3600),
                           endDate: start.addingTimeInterval(3 * 3600), type: .deep),
                SleepStage(startDate: start.addingTimeInterval(3 * 3600),
                           endDate: start.addingTimeInterval(3.5 * 3600), type: .awake),
                SleepStage(startDate: start.addingTimeInterval(3.5 * 3600),
                           endDate: start.addingTimeInterval(4.5 * 3600), type: .rem),
                SleepStage(startDate: start.addingTimeInterval(4.5 * 3600),
                           endDate: start.addingTimeInterval(8 * 3600), type: .core),
            ]
        )
    }

    @Test func snapshotCarriesStageDurationsAsSharesOfTotalSleep() {
        let night = calendar.startOfDay(for: date("2026-05-03 06:00"))
        let session = session(nightDate: night)

        let snapshot = SleepWidgetSnapshot(session: session, generatedAt: date("2026-05-03 07:00"))

        #expect(snapshot.nightDate == night)
        #expect(snapshot.totalSleep == session.totalSleep)
        #expect(snapshot.deep?.duration == 3600)
        #expect(snapshot.rem?.duration == 3600)
        #expect(snapshot.awake?.duration == 1800)

        // Core + deep + REM are shares of total sleep and must sum to 1.
        let sleepRatios = snapshot.slices
            .filter { $0.stage != .awake }
            .reduce(0) { $0 + $1.ratio }
        #expect(abs(sleepRatios - 1.0) < 1e-9)
    }

    @Test func stagesWithNoTimeAreOmittedRatherThanDrawnAsZeroWidth() {
        let night = calendar.startOfDay(for: date("2026-05-03 06:00"))
        let start = date("2026-05-02 23:00")
        let coreOnly = SleepSession(
            nightDate: night,
            stages: [
                SleepStage(startDate: start, endDate: start.addingTimeInterval(6 * 3600), type: .core)
            ]
        )

        let snapshot = SleepWidgetSnapshot(session: coreOnly)

        #expect(snapshot.slices.count == 1)
        #expect(snapshot.slices.first?.stage == .core)
        #expect(snapshot.deep == nil)
        #expect(snapshot.awake == nil)
    }

    @Test func snapshotWithNoSleepDoesNotDivideByZero() {
        let night = calendar.startOfDay(for: date("2026-05-03 06:00"))
        let start = date("2026-05-02 23:00")
        let awakeOnly = SleepSession(
            nightDate: night,
            stages: [
                SleepStage(startDate: start, endDate: start.addingTimeInterval(3600), type: .awake)
            ]
        )

        let snapshot = SleepWidgetSnapshot(session: awakeOnly)

        #expect(snapshot.totalSleep == 0)
        #expect(snapshot.awake?.ratio == 0)
        #expect(snapshot.slices.allSatisfy { $0.ratio.isFinite })
    }

    // MARK: - Freshness

    @Test func lastNightReadsAsCurrentAndOlderNightsCarryTheirDate() {
        let now = date("2026-05-03 06:00")
        let lastNight = SleepWidgetSnapshot.sample(nightDate: calendar.startOfDay(for: now))

        #expect(lastNight.isCurrent(now: now, calendar: calendar))
        #expect(lastNight.nightsAgo(now: now, calendar: calendar) == 0)
        #expect(lastNight.stalenessBadge(now: now, calendar: calendar) == nil)
        #expect(lastNight.dateLabel(now: now, calendar: calendar) == "Last night")

        // The 5:30am case: the watch has not synced, so the newest night on
        // file is the one before. The widget must not present that as current.
        let nightBefore = SleepWidgetSnapshot.sample(
            nightDate: calendar.startOfDay(for: date("2026-05-02 06:00"))
        )

        #expect(!nightBefore.isCurrent(now: now, calendar: calendar))
        #expect(nightBefore.nightsAgo(now: now, calendar: calendar) == 1)
        #expect(nightBefore.stalenessBadge(now: now, calendar: calendar) == "1d")
        #expect(nightBefore.dateLabel(now: now, calendar: calendar) != "Last night")
    }

    @Test func stalenessCountsWholeDaysBack() {
        let now = date("2026-05-03 06:00")
        let threeNightsAgo = SleepWidgetSnapshot.sample(
            nightDate: calendar.startOfDay(for: date("2026-04-30 06:00"))
        )

        #expect(threeNightsAgo.nightsAgo(now: now, calendar: calendar) == 3)
        #expect(threeNightsAgo.stalenessBadge(now: now, calendar: calendar) == "3d")
    }

    // MARK: - Store

    @Test func snapshotSurvivesAWriteReadRoundTrip() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SleepWidgetSnapshotStore(directory: directory)
        let original = SleepWidgetSnapshot(session: session(
            nightDate: calendar.startOfDay(for: date("2026-05-03 06:00"))
        ))

        #expect(store.write(original))
        #expect(store.read() == original)
    }

    @Test func readingBeforeAnythingIsWrittenReturnsNil() {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let store = SleepWidgetSnapshotStore(directory: directory)

        #expect(store.read() == nil)
    }

    @Test func writingWithoutAContainerFailsWithoutCrashing() {
        let store = SleepWidgetSnapshotStore(directory: nil)

        #expect(!store.write(.sample()))
        #expect(store.read() == nil)
    }

    // MARK: - Formatting

    @Test func compactDurationFitsTheCircularGauge() {
        #expect((7 * 3600 + 12 * 60).compactDuration == "7h")
        #expect((48.0 * 60).compactDuration == "48m")
        #expect(TimeInterval(0).compactDuration == "0m")
    }
}
