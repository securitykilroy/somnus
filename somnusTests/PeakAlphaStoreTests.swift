import Foundation
import Testing
@testable import somnus

struct PeakAlphaStoreTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @MainActor
    @Test func startsEmptyWithNoEntries() throws {
        let store = try PeakAlphaStore(inMemory: true, useCloudKit: false)
        #expect(store.entries.isEmpty)
    }

    @MainActor
    @Test func addPersistsEntryAndIsFetchableAfterReload() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let backupURL = directory.appendingPathComponent("PeakAlphaEntries.backup.json")
        let store = try PeakAlphaStore(
            inMemory: true,
            useCloudKit: false,
            backupJSONFileURL: backupURL
        )
        let day = Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 9))!

        try store.add(date: day, value: 8.4, note: "Morning session")

        #expect(store.entries.count == 1)
        #expect(store.entries.first?.value == 8.4)
        #expect(store.entries.first?.note == "Morning session")

        try store.load()
        #expect(store.entries.count == 1)
        #expect(store.entries.first?.value == 8.4)
        #expect(FileManager.default.fileExists(atPath: backupURL.path))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backupEntries = try decoder.decode([PeakAlphaEntry].self, from: Data(contentsOf: backupURL))
        #expect(backupEntries.count == 1)
        #expect(backupEntries.first?.value == 8.4)
    }

    @MainActor
    @Test func addingForSameDayReplacesExistingEntry() throws {
        let store = try PeakAlphaStore(inMemory: true, useCloudKit: false)
        let morning = Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 8))!
        let evening = Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 20))!

        try store.add(date: morning, value: 7.0)
        try store.add(date: evening, value: 9.5)

        #expect(store.entries.count == 1)
        #expect(store.entries.first?.value == 9.5)
    }

    @MainActor
    @Test func addStoresEntryAtStartOfCalendarDay() throws {
        let store = try PeakAlphaStore(inMemory: true, useCloudKit: false)
        let afternoon = Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 15, minute: 30))!

        let entry = try store.add(date: afternoon, value: 7.2)

        #expect(entry.date == Calendar.current.startOfDay(for: afternoon))
        #expect(store.entries.first?.date == Calendar.current.startOfDay(for: afternoon))
    }

    @MainActor
    @Test func entriesAreSortedNewestFirst() throws {
        let store = try PeakAlphaStore(inMemory: true, useCloudKit: false)
        let earlier = Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let later = Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!

        try store.add(date: earlier, value: 6.0)
        try store.add(date: later, value: 7.5)

        #expect(store.entries.map(\.value) == [7.5, 6.0])
    }

    @MainActor
    @Test func removeDeletesEntryAndPersists() throws {
        let store = try PeakAlphaStore(inMemory: true, useCloudKit: false)
        let day = Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!

        let entry = try store.add(date: day, value: 6.5)
        try store.remove(entry)

        #expect(store.entries.isEmpty)

        try store.load()
        #expect(store.entries.isEmpty)
    }

    @MainActor
    @Test func addBeforePersistentStoreLoadsThrowsReadableError() throws {
        let store = try PeakAlphaStore(inMemory: false, useCloudKit: false)
        let day = Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!

        #expect(throws: PeakAlphaStore.StoreUnavailableError.self) {
            try store.add(date: day, value: 8.4)
        }
    }

    @MainActor
    @Test func migratesLegacyJSONWrittenWithDefaultDateEncoding() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacyURL = directory.appendingPathComponent("PeakAlphaEntries.json")
        let storeURL = directory.appendingPathComponent("SomnusPeakAlphaModel.sqlite")
        let day = Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 9))!
        let legacyEntries = [
            PeakAlphaEntry(date: day, value: 10.2, note: "Default JSON date strategy")
        ]
        let data = try JSONEncoder().encode(legacyEntries)
        try data.write(to: legacyURL)

        let store = try PeakAlphaStore(
            inMemory: false,
            useCloudKit: false,
            storeURL: storeURL,
            legacyJSONFileURLs: [legacyURL]
        )
        try await store.loadAsync()

        #expect(store.entries.count == 1)
        #expect(store.entries.first?.value == 10.2)
        #expect(FileManager.default.fileExists(atPath: legacyURL.path))
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("PeakAlphaEntries.migrated.json").path
        ))
    }

    @MainActor
    @Test func migratesPreviouslyArchivedLegacyJSON() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let migratedURL = directory.appendingPathComponent("PeakAlphaEntries.migrated.json")
        let storeURL = directory.appendingPathComponent("SomnusPeakAlphaModel.sqlite")
        let day = Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 9))!
        let legacyEntries = [
            PeakAlphaEntry(date: day, value: 7.8, note: "Already archived")
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(legacyEntries)
        try data.write(to: migratedURL)

        let store = try PeakAlphaStore(
            inMemory: false,
            useCloudKit: false,
            storeURL: storeURL,
            legacyJSONFileURLs: [migratedURL]
        )
        try await store.loadAsync()

        #expect(store.entries.count == 1)
        #expect(store.entries.first?.value == 7.8)
    }

    @MainActor
    @Test func migratesBackupJSONWhenCoreDataStoreIsEmpty() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let backupURL = directory.appendingPathComponent("PeakAlphaEntries.backup.json")
        let storeURL = directory.appendingPathComponent("SomnusPeakAlphaModel.sqlite")
        let day = Self.calendar.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 9))!
        let backupEntries = [
            PeakAlphaEntry(date: day, value: 11.4, note: "Backup")
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backupEntries)
        try data.write(to: backupURL)

        let store = try PeakAlphaStore(
            inMemory: false,
            useCloudKit: false,
            storeURL: storeURL,
            legacyJSONFileURLs: [backupURL],
            backupJSONFileURL: backupURL
        )
        try await store.loadAsync()

        #expect(store.entries.count == 1)
        #expect(store.entries.first?.value == 11.4)
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PeakAlphaStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
