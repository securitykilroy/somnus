import Foundation
import Testing
@testable import somnus

struct SleepIntentStoreTests {
    @MainActor
    @Test func inMemoryStorePersistsAndFetchesIntentEvents() throws {
        let store = try SleepIntentStore(inMemory: true, useCloudKit: false)
        let timestamp = Date(timeIntervalSince1970: 1_779_000_000)

        try store.add(kind: .tryingToSleep, timestamp: timestamp, note: "Lights out")
        try store.add(kind: .awake, timestamp: timestamp.addingTimeInterval(8 * 3600), note: nil)

        let events = store.events

        #expect(events.count == 2)
        #expect(events.map(\.kind) == [.awake, .tryingToSleep])
        #expect(events.last?.timestamp == timestamp)
        #expect(events.last?.note == "Lights out")
    }

    @MainActor
    @Test func inMemoryStorePublishesLatestLatencySnapshots() throws {
        let store = try SleepIntentStore(inMemory: true, useCloudKit: false)
        let night = Date(timeIntervalSince1970: 1_779_000_000)
        let older = SleepLatencyRecord(
            sessionID: UUID(),
            nightDate: night,
            intentTime: night.addingTimeInterval(22 * 3600),
            firstSleepTime: night.addingTimeInterval(22 * 3600 + 25 * 60),
            latency: 25 * 60,
            intentEventID: UUID(),
            appleLatency: 0
        )
        let newer = SleepLatencyRecord(
            sessionID: UUID(),
            nightDate: night.addingTimeInterval(24 * 3600),
            intentTime: night.addingTimeInterval(46 * 3600),
            firstSleepTime: night.addingTimeInterval(46 * 3600 + 41 * 60),
            latency: 41 * 60,
            intentEventID: UUID(),
            appleLatency: 12 * 60
        )

        try store.saveLatencySnapshots(from: [older, newer])

        #expect(store.latencySnapshots.count == 2)
        #expect(store.latencySnapshots.first?.nightDate == newer.nightDate)
        #expect(store.latencySnapshots.first?.latency == 41 * 60.0)
        #expect(store.latencySnapshots.first?.appleLatency == 12 * 60.0)

        try store.saveLatencySnapshots(from: [older])

        #expect(store.latencySnapshots.count == 1)
        #expect(store.latencySnapshots.first?.nightDate == older.nightDate)
    }
}
