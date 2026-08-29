import Foundation

/// Reads and writes the meal log in the shared App Group container.
///
/// A file rather than the CloudKit Core Data stack the app uses elsewhere: the
/// whole point of meal logging is that it happens from a widget button or a
/// Siri phrase without the app ever coming up, and spinning a
/// `NSPersistentCloudKitContainer` inside a widget tap would cost more than the
/// tap is worth. The payload is a few entries a day, so a single JSON array
/// rewritten on each edit is cheap.
///
/// Writes go through `NSFileCoordinator` because the app process and the widget
/// extension can both append: an uncoordinated read-modify-write would lose an
/// entry whenever the two overlapped. Injecting `directory` lets the round trip
/// be tested against a temporary folder without an App Group.
nonisolated struct MealLogStore {
    static let appGroupIdentifier = "group.com.washere.somnus"
    private static let filename = "meal-log.json"

    private let directory: URL?

    init(directory: URL? = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: MealLogStore.appGroupIdentifier
    )) {
        self.directory = directory
    }

    private var fileURL: URL? {
        directory?.appendingPathComponent(Self.filename)
    }

    /// Every entry, newest first.
    func read() -> [MealEvent] {
        guard let fileURL else { return [] }

        var events: [MealEvent] = []
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &coordinatorError) { url in
            events = Self.decode(at: url)
        }
        return events
    }

    /// Entries falling inside the calendar day containing `date`, newest first.
    func events(on date: Date, calendar: Calendar = .current) -> [MealEvent] {
        read().filter { calendar.isDate($0.timestamp, inSameDayAs: date) }
    }

    @discardableResult
    func append(note: String = "", at timestamp: Date = Date()) -> MealEvent? {
        let event = MealEvent(timestamp: timestamp, note: note)
        let saved = mutate { events in
            events.append(event)
        }
        return saved ? event : nil
    }

    /// Applies only the fields that are non-`nil`, so a caller editing the time
    /// does not have to restate the note.
    @discardableResult
    func update(id: UUID, note: String? = nil, timestamp: Date? = nil) -> Bool {
        var found = false
        let saved = mutate { events in
            guard let index = events.firstIndex(where: { $0.id == id }) else { return }
            found = true
            if let note {
                events[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let timestamp {
                events[index].timestamp = timestamp
            }
            events[index].updatedAt = Date()
        }
        return saved && found
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        var found = false
        let saved = mutate { events in
            let before = events.count
            events.removeAll { $0.id == id }
            found = events.count != before
        }
        return saved && found
    }

    /// Removes the newest entry and hands it back, so a caller can say what it
    /// undid. Bounded by `within` because "undo" is meant for a mis-tap seconds
    /// old, not for pruning last week.
    @discardableResult
    func removeMostRecent(within: TimeInterval = 15 * 60, now: Date = Date()) -> MealEvent? {
        var removed: MealEvent?
        let saved = mutate { events in
            guard let index = events.indices.max(by: { events[$0].createdAt < events[$1].createdAt }),
                  now.timeIntervalSince(events[index].createdAt) <= within else { return }
            removed = events.remove(at: index)
        }
        return saved ? removed : nil
    }

    /// The read, the mutation and the write all happen inside one coordinated
    /// write so a concurrent append from the other process waits rather than
    /// overwriting.
    private func mutate(_ body: (inout [MealEvent]) -> Void) -> Bool {
        guard let fileURL, let directory else { return false }

        var succeeded = false
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: fileURL,
            options: .forMerging,
            error: &coordinatorError
        ) { url in
            var events = Self.decode(at: url)
            body(&events)
            events.sort { $0.timestamp > $1.timestamp }

            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = try Self.encoder.encode(events)
                try data.write(to: url, options: .atomic)
                succeeded = true
            } catch {
                succeeded = false
            }
        }
        return succeeded && coordinatorError == nil
    }

    private static func decode(at url: URL) -> [MealEvent] {
        guard let data = try? Data(contentsOf: url),
              let events = try? decoder.decode([MealEvent].self, from: data) else { return [] }
        return events.sorted { $0.timestamp > $1.timestamp }
    }

    // Default date handling on purpose, matching SleepWidgetSnapshotStore:
    // ISO-8601 truncates sub-second precision, so an entry would not survive a
    // round trip unchanged.
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}
