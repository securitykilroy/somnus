import Foundation

/// Moves the widget snapshot between the app and the widget extension through
/// the shared App Group container.
///
/// A file rather than shared `UserDefaults`: the payload is a single value with
/// a natural JSON shape, and injecting `directory` lets the round-trip be tested
/// against a temporary folder without an App Group.
nonisolated struct SleepWidgetSnapshotStore {
    static let appGroupIdentifier = "group.com.washere.somnus"
    private static let filename = "sleep-widget-snapshot.json"

    private let directory: URL?

    init(directory: URL? = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: SleepWidgetSnapshotStore.appGroupIdentifier
    )) {
        self.directory = directory
    }

    private var fileURL: URL? {
        directory?.appendingPathComponent(Self.filename)
    }

    func read() -> SleepWidgetSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? Self.decoder.decode(SleepWidgetSnapshot.self, from: data)
    }

    /// Failures are swallowed on purpose: a snapshot that cannot be written
    /// leaves the widget showing the previous night, which is a better outcome
    /// than disturbing the app's load.
    @discardableResult
    func write(_ snapshot: SleepWidgetSnapshot) -> Bool {
        guard let fileURL, let directory else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // Default date handling on purpose: ISO-8601 truncates sub-second
    // precision, so a snapshot would not survive a round trip unchanged.
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}
