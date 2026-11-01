import Foundation

nonisolated struct HealthKitSleepSampleRecord: Codable, Equatable, Sendable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let value: Int
    let sourceName: String?
}

/// A derived-data cache for HealthKit reads. The JSON file is disposable: the
/// HealthKit store remains authoritative, while this snapshot lets cold starts
/// resume anchored queries and avoid re-enriching unchanged nights.
nonisolated final class HealthDataCache: @unchecked Sendable {
    private struct MovementEntry: Codable {
        let fingerprint: String
        let samples: [MovementSample]
        let refreshedAt: Date
    }

    private struct MetricEntry: Codable {
        var samples: [CachedMetricSample]
        var refreshedThrough: Date
    }

    private struct CachedMetricSample: Codable {
        let date: Date
        let value: Double

        init(_ sample: DailyMetricSample) {
            date = sample.date
            value = sample.value
        }

        var valueObject: DailyMetricSample {
            DailyMetricSample(date: date, value: value)
        }
    }

    private struct State: Codable {
        var sleepAnchorData: Data?
        var sleepSamples: [HealthKitSleepSampleRecord] = []
        var movementByNight: [String: MovementEntry] = [:]
        var metricsByKey: [String: MetricEntry] = [:]
    }

    private struct SleepState: Codable {
        var anchorData: Data?
        var samples: [HealthKitSleepSampleRecord]
    }

    private struct MovementState: Codable {
        var byNight: [String: MovementEntry]
    }

    private struct MetricsState: Codable {
        var byKey: [String: MetricEntry]
    }

    private let fileURL: URL?
    private let lock = NSLock()
    private var state: State

    init(fileURL: URL?) {
        self.fileURL = fileURL
        var loaded = State()
        if let fileURL {
            if let sleep = Self.decode(SleepState.self, from: fileURL) {
                loaded.sleepAnchorData = sleep.anchorData
                loaded.sleepSamples = sleep.samples
            }
            if let movement = Self.decode(MovementState.self, from: Self.movementFileURL(for: fileURL)) {
                loaded.movementByNight = movement.byNight
            }
            if let metrics = Self.decode(MetricsState.self, from: Self.metricsFileURL(for: fileURL)) {
                loaded.metricsByKey = metrics.byKey
            }
        }
        state = loaded
    }

    static func defaultFileURL() -> URL? {
        guard let directory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else { return nil }
        return directory
            .appendingPathComponent("Somnus", isDirectory: true)
            .appendingPathComponent("health-data-cache-v1.json")
    }

    func sleepSnapshot() -> (anchorData: Data?, samples: [HealthKitSleepSampleRecord]) {
        lock.lock()
        defer { lock.unlock() }
        return (state.sleepAnchorData, state.sleepSamples)
    }

    func saveSleepSnapshot(anchorData: Data?, samples: [HealthKitSleepSampleRecord]) {
        lock.lock()
        guard state.sleepAnchorData != anchorData || state.sleepSamples != samples else {
            lock.unlock()
            return
        }
        state.sleepAnchorData = anchorData
        state.sleepSamples = samples
        persistLocked(
            SleepState(anchorData: anchorData, samples: samples),
            to: fileURL
        )
        lock.unlock()
    }

    func movement(
        for session: SleepSession,
        now: Date,
        maxAge: TimeInterval
    ) -> [MovementSample]? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = state.movementByNight[session.id.uuidString],
              entry.fingerprint == Self.fingerprint(for: session),
              now.timeIntervalSince(entry.refreshedAt) >= 0,
              now.timeIntervalSince(entry.refreshedAt) <= maxAge else {
            return nil
        }
        return entry.samples
    }

    func saveMovement(
        _ samples: [MovementSample],
        for session: SleepSession,
        refreshedAt: Date
    ) {
        saveMovement([(session: session, samples: samples)], refreshedAt: refreshedAt)
    }

    func saveMovement(
        _ updates: [(session: SleepSession, samples: [MovementSample])],
        refreshedAt: Date
    ) {
        lock.lock()
        for update in updates {
            state.movementByNight[update.session.id.uuidString] = MovementEntry(
                fingerprint: Self.fingerprint(for: update.session),
                samples: update.samples,
                refreshedAt: refreshedAt
            )
        }
        persistLocked(
            MovementState(byNight: state.movementByNight),
            to: fileURL.map(Self.movementFileURL(for:))
        )
        lock.unlock()
    }

    func metricRefreshStart(
        forKey key: String,
        requestedStart: Date,
        end: Date,
        overlap: TimeInterval,
        calendar: Calendar = .current
    ) -> Date {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = state.metricsByKey[key] else { return requestedStart }
        let overlapStart = calendar.startOfDay(
            for: entry.refreshedThrough.addingTimeInterval(-overlap)
        )
        return max(requestedStart, min(end, overlapStart))
    }

    func mergeMetricSamples(
        _ samples: [DailyMetricSample],
        forKey key: String,
        replacingFrom replacementStart: Date,
        refreshedThrough: Date
    ) {
        lock.lock()
        var retained = state.metricsByKey[key]?.samples.filter { $0.date < replacementStart } ?? []
        retained.append(contentsOf: samples.map(CachedMetricSample.init))
        retained.sort { $0.date < $1.date }
        state.metricsByKey[key] = MetricEntry(
            samples: retained,
            refreshedThrough: refreshedThrough
        )
        persistLocked(
            MetricsState(byKey: state.metricsByKey),
            to: fileURL.map(Self.metricsFileURL(for:))
        )
        lock.unlock()
    }

    func metricSamples(forKey key: String, start: Date, end: Date) -> [DailyMetricSample] {
        lock.lock()
        defer { lock.unlock() }
        return (state.metricsByKey[key]?.samples ?? [])
            .filter { $0.date >= start && $0.date < end }
            .map(\.valueObject)
    }

    private static func fingerprint(for session: SleepSession) -> String {
        session.stages
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.endDate < rhs.endDate
            }
            .map { stage in
                [
                    (stage.healthKitUUID ?? stage.id).uuidString,
                    stage.startDate.timeIntervalSinceReferenceDate.description,
                    stage.endDate.timeIntervalSinceReferenceDate.description,
                    stage.type.rawValue,
                ].joined(separator: "|")
            }
            .joined(separator: ";")
    }

    private static func movementFileURL(for baseURL: URL) -> URL {
        baseURL.deletingPathExtension().appendingPathExtension("movement.json")
    }

    private static func metricsFileURL(for baseURL: URL) -> URL {
        baseURL.deletingPathExtension().appendingPathExtension("metrics.json")
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func persistLocked<Value: Encodable>(_ value: Value, to destination: URL?) {
        guard let destination else { return }
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(value)
            try data.write(to: destination, options: .atomic)
        } catch {
            // This is a performance cache, never the source of truth. A failed
            // cache write must not turn a successful HealthKit load into an app
            // error or risk user-owned data.
        }
    }
}
