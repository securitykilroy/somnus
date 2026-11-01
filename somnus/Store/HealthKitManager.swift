import Foundation
import HealthKit

nonisolated final class HealthKitManager: @unchecked Sendable {
    private let store = HKHealthStore()
    private let observerLock = NSLock()
    private let sleepStateLock = NSLock()
    private let healthDataCache: HealthDataCache
    /// Guarded by `observerLock`, and reached from HealthKit's own callback
    /// queue rather than the main actor.
    nonisolated(unsafe) private var sleepObserverQuery: HKObserverQuery?
    /// The anchor and sample cache are updated together under `sleepStateLock`.
    /// The initial query fills the cache; later refreshes ask HealthKit only for
    /// additions and deletions since that query.
    nonisolated(unsafe) private var sleepQueryAnchor: HKQueryAnchor?
    nonisolated(unsafe) private var cachedSleepSamples: [UUID: HealthKitSleepSampleRecord] = [:]

    struct TimedQuantitySample {
        let startDate: Date
        let value: Double
    }

    init(cacheURL: URL? = HealthDataCache.defaultFileURL()) {
        let cache = HealthDataCache(fileURL: cacheURL)
        healthDataCache = cache
        let snapshot = cache.sleepSnapshot()
        // Treat the on-disk cache as untrusted derived data. A truncated or
        // manually edited cache must never crash launch because it happens to
        // contain the same HealthKit UUID twice; the newest decoded value wins.
        cachedSleepSamples = snapshot.samples.reduce(into: [:]) { records, sample in
            records[sample.id] = sample
        }
        if let anchorData = snapshot.anchorData {
            sleepQueryAnchor = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: HKQueryAnchor.self,
                from: anchorData
            )
        }
    }

    @MainActor
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        let types: Set<HKObjectType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.categoryType(forIdentifier: .appleStandHour)!,
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
        ]
        try await store.requestAuthorization(toShare: [], read: types)
    }

    /// Watches for sleep samples landing in HealthKit and calls `onChange`.
    ///
    /// The watch does not write a night's stage samples until the sleep session
    /// closes, and those samples then need to sync to the phone — often long
    /// after the app was last opened. Without an observer the app only ever sees
    /// whatever happened to be in the store at launch.
    ///
    /// Registration is idempotent; calling it again is a no-op.
    func startObservingSleepChanges(onChange: @escaping @Sendable () async -> Void) async {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        guard let query = makeObserverQueryIfNeeded(for: sleepType, onChange: onChange) else { return }

        store.execute(query)
        await enableBackgroundDelivery(for: sleepType)
    }

    /// Synchronous and `nonisolated` on purpose: `NSLock` may not be held across
    /// a suspension point, so the registration check lives here rather than in
    /// the `async` caller.
    ///
    /// Returns `nil` when an observer is already registered.
    nonisolated private func makeObserverQueryIfNeeded(
        for sleepType: HKSampleType,
        onChange: @escaping @Sendable () async -> Void
    ) -> HKObserverQuery? {
        observerLock.lock()
        defer { observerLock.unlock() }

        guard sleepObserverQuery == nil else { return nil }

        let query = HKObserverQuery(sampleType: sleepType, predicate: nil) { _, completionHandler, error in
            guard error == nil else {
                // Still acknowledge, otherwise HealthKit keeps re-delivering
                // this update with backoff.
                completionHandler()
                return
            }
            Task { @MainActor in
                await onChange()
                // Only acknowledge once the reload is done — on a background
                // wake this is what keeps the app alive long enough to finish.
                completionHandler()
            }
        }
        sleepObserverQuery = query
        return query
    }

    /// `.hourly` is the finest frequency HealthKit honors for sleep; asking for
    /// `.immediate` silently degrades to the same thing.
    private func enableBackgroundDelivery(for type: HKObjectType) async {
        await withCheckedContinuation { continuation in
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in
                continuation.resume()
            }
        }
    }

    func fetchAllSleepSamples() async throws -> [SleepSession] {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let anchor = currentSleepQueryAnchor()

        let changes: (added: [HKCategorySample], deletedIDs: Set<UUID>, anchor: HKQueryAnchor?) =
            try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: sleepType,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit,
                resultsHandler: { _, added, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (
                        added: (added ?? []).compactMap { $0 as? HKCategorySample },
                        deletedIDs: Set((deleted ?? []).map(\.uuid)),
                        anchor: newAnchor
                    ))
                }
            })
            store.execute(query)
        }

        let sampleRecords = applySleepChanges(changes)
        return Self.groupIntoSessions(sampleRecords, movementSamples: [])
    }

    private func currentSleepQueryAnchor() -> HKQueryAnchor? {
        sleepStateLock.lock()
        defer { sleepStateLock.unlock() }
        return sleepQueryAnchor
    }

    private func applySleepChanges(
        _ changes: (added: [HKCategorySample], deletedIDs: Set<UUID>, anchor: HKQueryAnchor?)
    ) -> [HealthKitSleepSampleRecord] {
        sleepStateLock.lock()
        cachedSleepSamples = Self.mergeSleepRecords(
            existing: cachedSleepSamples,
            added: changes.added.map(Self.sleepRecord(from:)),
            deletedIDs: changes.deletedIDs
        )
        sleepQueryAnchor = changes.anchor
        let records = cachedSleepSamples.values.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let anchorData = changes.anchor.flatMap {
            try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
        }
        sleepStateLock.unlock()

        healthDataCache.saveSleepSnapshot(anchorData: anchorData, samples: records)
        return records
    }

    private static func sleepRecord(from sample: HKCategorySample) -> HealthKitSleepSampleRecord {
        HealthKitSleepSampleRecord(
            id: sample.uuid,
            startDate: sample.startDate,
            endDate: sample.endDate,
            value: sample.value,
            sourceName: sample.sourceRevision.source.name
        )
    }

    private static func mergeSleepRecords(
        existing: [UUID: HealthKitSleepSampleRecord],
        added: [HealthKitSleepSampleRecord],
        deletedIDs: Set<UUID>
    ) -> [UUID: HealthKitSleepSampleRecord] {
        var merged = existing
        for id in deletedIDs { merged.removeValue(forKey: id) }
        for sample in added { merged[sample.id] = sample }
        return merged
    }

    static func mergeSleepSamples(
        existing: [UUID: HKCategorySample],
        added: [HKCategorySample],
        deletedIDs: Set<UUID>
    ) -> [UUID: HKCategorySample] {
        var merged = existing
        for id in deletedIDs {
            merged.removeValue(forKey: id)
        }
        for sample in added {
            merged[sample.uuid] = sample
        }
        return merged
    }

    /// Sleep windows per steps, distance, or stand-hour query. A three-year
    /// history now costs three queries per chunk instead of three per night.
    private static let movementWindowChunkSize = 60

    /// Sleep windows per heart-rate query.
    private static let heartRateWindowChunkSize = 60

    func enrichSessionsWithMovement(_ sessions: [SleepSession]) async throws -> [SleepSession] {
        guard !sessions.isEmpty else { return [] }
        var enriched = sessions
        let indicesByID = Dictionary(uniqueKeysWithValues: sessions.enumerated().map { ($0.element.id, $0.offset) })
        let now = Date()
        var uncached: [SleepSession] = []

        for session in sessions {
            let age = now.timeIntervalSince(session.nightDate)
            let maxCacheAge: TimeInterval = age < 3 * 86_400 ? 6 * 3600 : 30 * 86_400
            if let samples = healthDataCache.movement(
                for: session,
                now: now,
                maxAge: maxCacheAge
            ), let index = indicesByID[session.id] {
                enriched[index] = SleepSession(copying: session, movementSamples: samples)
            } else {
                uncached.append(session)
            }
        }

        for batch in Self.movementSessionBatches(uncached) {
            let windows = batch.compactMap(AwakeEventDetector.sleepMovementEvidenceWindow(for:))
            async let movementSamples = fetchMovementSamples(in: windows)
            async let standSamples = fetchStandHourSamples(in: windows)
            let samples = try await movementSamples + standSamples

            var cacheUpdates: [(session: SleepSession, samples: [MovementSample])] = []
            for session in batch {
                guard let index = indicesByID[session.id],
                      let window = AwakeEventDetector.sleepMovementEvidenceWindow(for: session) else {
                    continue
                }
                let sessionSamples = samples.filter {
                    $0.startDate < window.end && $0.endDate > window.start
                }
                enriched[index] = SleepSession(copying: session, movementSamples: sessionSamples)
                cacheUpdates.append((session: session, samples: sessionSamples))
            }
            healthDataCache.saveMovement(cacheUpdates, refreshedAt: now)
        }

        return enriched
    }

    static func movementSessionBatches(_ sessions: [SleepSession]) -> [[SleepSession]] {
        stride(from: 0, to: sessions.count, by: movementWindowChunkSize).map { offset in
            Array(sessions[offset..<min(offset + movementWindowChunkSize, sessions.count)])
        }
    }

    private func fetchMovementSamples(in windows: [DateInterval]) async throws -> [MovementSample] {
        guard !windows.isEmpty else { return [] }

        async let steps = fetchQuantityMovementSamples(
            identifier: .stepCount,
            unit: .count(),
            in: windows
        ) { quantitySample, value in
            MovementSample(
                startDate: quantitySample.startDate,
                endDate: quantitySample.endDate,
                stepCount: value,
                sourceName: quantitySample.sourceRevision.source.name
            )
        }
        async let distance = fetchQuantityMovementSamples(
            identifier: .distanceWalkingRunning,
            unit: .meter(),
            in: windows
        ) { quantitySample, value in
            MovementSample(
                startDate: quantitySample.startDate,
                endDate: quantitySample.endDate,
                distance: value,
                sourceName: quantitySample.sourceRevision.source.name
            )
        }

        return try await steps + distance
    }

    private func fetchQuantityMovementSamples(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        in windows: [DateInterval],
        makeSample: @escaping @Sendable (HKQuantitySample, Double) -> MovementSample
    ) async throws -> [MovementSample] {
        let quantityType = HKQuantityType.quantityType(forIdentifier: identifier)!
        let predicate = Self.samplePredicate(for: windows)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result ?? [])
                }
            }
            store.execute(query)
        }

        return samples.compactMap { sample in
            guard let quantitySample = sample as? HKQuantitySample else { return nil }
            let value = quantitySample.quantity.doubleValue(for: unit)
            guard value > 0 else { return nil }
            return makeSample(quantitySample, value)
        }
    }

    private func fetchStandHourSamples(in windows: [DateInterval]) async throws -> [MovementSample] {
        guard !windows.isEmpty else { return [] }

        let standType = HKObjectType.categoryType(forIdentifier: .appleStandHour)!
        let predicate = Self.samplePredicate(for: windows)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: standType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result ?? [])
                }
            }
            store.execute(query)
        }

        return samples.compactMap { sample in
            guard let categorySample = sample as? HKCategorySample,
                  categorySample.value == HKCategoryValueAppleStandHour.stood.rawValue else {
                return nil
            }

            return MovementSample(
                startDate: categorySample.startDate,
                endDate: categorySample.endDate,
                standHourCount: 1,
                sourceName: categorySample.sourceRevision.source.name
            )
        }
    }

    private static func samplePredicate(for windows: [DateInterval]) -> NSPredicate {
        let predicates = windows.map {
            HKQuery.predicateForSamples(withStart: $0.start, end: $0.end)
        }
        if predicates.count == 1 {
            return predicates[0]
        }
        return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }

    private func fetchCumulativeQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> Double {
        let quantityType = HKQuantityType.quantityType(forIdentifier: identifier)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    private static func groupIntoSessions(
        _ samples: [HealthKitSleepSampleRecord],
        movementSamples: [MovementSample]
    ) -> [SleepSession] {
        let stages = samples.compactMap { sample -> SleepStage? in
            guard let stageType = SleepStageType.from(sample.value) else { return nil }
            return SleepStage(
                id: sample.id,
                startDate: sample.startDate,
                endDate: sample.endDate,
                type: stageType,
                sourceName: sample.sourceName,
                healthKitUUID: sample.id
            )
        }
        return SleepSessionGrouper.primarySessions(
            from: stages,
            movementSamples: movementSamples
        )
    }

    func fetchDailyCalories(start: Date, end: Date) async throws -> [DailyMetricSample] {
        let cacheKey = HKQuantityTypeIdentifier.activeEnergyBurned.rawValue
        let refreshStart = healthDataCache.metricRefreshStart(
            forKey: cacheKey,
            requestedStart: start,
            end: end,
            overlap: 3 * 86_400
        )
        if refreshStart < end {
            let fresh = try await queryDailyCalories(start: refreshStart, end: end)
            healthDataCache.mergeMetricSamples(
                fresh,
                forKey: cacheKey,
                replacingFrom: refreshStart,
                refreshedThrough: end
            )
        }
        return healthDataCache.metricSamples(forKey: cacheKey, start: start, end: end)
    }

    private func queryDailyCalories(start: Date, end: Date) async throws -> [DailyMetricSample] {
        let calorieType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let raw: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: calorieType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result ?? []) }
            }
            store.execute(query)
        }

        let calendar = Calendar.current
        var byDay: [Date: Double] = [:]
        for sample in raw.compactMap({ $0 as? HKQuantitySample }) {
            let day = calendar.startOfDay(for: sample.startDate)
            byDay[day, default: 0] += sample.quantity.doubleValue(for: .kilocalorie())
        }
        let dailyCalories = byDay
            .map { DailyMetricSample(date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
        return MetricDataQuality.plausibleDailyActiveCalories(dailyCalories)
    }

    /// Sums Mindful Minutes (`HKCategoryTypeIdentifier.mindfulSession`) sessions
    /// by calendar day. Most meditation apps, including Muse, write session
    /// start/end times here even when richer metrics (like Peak Alpha) stay in
    /// their own store.
    func fetchDailyMindfulMinutes(start: Date, end: Date) async throws -> [DailyMetricSample] {
        let cacheKey = HKCategoryTypeIdentifier.mindfulSession.rawValue
        let refreshStart = healthDataCache.metricRefreshStart(
            forKey: cacheKey,
            requestedStart: start,
            end: end,
            overlap: 3 * 86_400
        )
        if refreshStart < end {
            let fresh = try await queryDailyMindfulMinutes(start: refreshStart, end: end)
            healthDataCache.mergeMetricSamples(
                fresh,
                forKey: cacheKey,
                replacingFrom: refreshStart,
                refreshedThrough: end
            )
        }
        return healthDataCache.metricSamples(forKey: cacheKey, start: start, end: end)
    }

    private func queryDailyMindfulMinutes(start: Date, end: Date) async throws -> [DailyMetricSample] {
        let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let raw: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: mindfulType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result ?? []) }
            }
            store.execute(query)
        }

        let calendar = Calendar.current
        var minutesByDay: [Date: Double] = [:]
        for sample in raw.compactMap({ $0 as? HKCategorySample }) {
            let day = calendar.startOfDay(for: sample.startDate)
            minutesByDay[day, default: 0] += sample.endDate.timeIntervalSince(sample.startDate) / 60
        }
        return minutesByDay
            .map { DailyMetricSample(date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
    }

    func fetchDailyMetrics(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> [DailyMetricSample] {
        let cacheKey = identifier.rawValue
        let refreshStart = healthDataCache.metricRefreshStart(
            forKey: cacheKey,
            requestedStart: start,
            end: end,
            overlap: 3 * 86_400
        )
        if refreshStart < end {
            let fresh = try await queryDailyMetrics(
                identifier: identifier,
                unit: unit,
                start: refreshStart,
                end: end
            )
            healthDataCache.mergeMetricSamples(
                fresh,
                forKey: cacheKey,
                replacingFrom: refreshStart,
                refreshedThrough: end
            )
        }
        return healthDataCache.metricSamples(forKey: cacheKey, start: start, end: end)
    }

    private func queryDailyMetrics(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> [DailyMetricSample] {
        let quantityType = HKQuantityType.quantityType(forIdentifier: identifier)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let raw: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result ?? []) }
            }
            store.execute(query)
        }

        let calendar = Calendar.current
        var byDay: [Date: [Double]] = [:]
        for sample in raw.compactMap({ $0 as? HKQuantitySample }) {
            let day = calendar.startOfDay(for: sample.startDate)
            byDay[day, default: []].append(sample.quantity.doubleValue(for: unit))
        }
        return byDay
            .map { DailyMetricSample(date: $0.key, value: $0.value.reduce(0, +) / Double($0.value.count)) }
            .sorted { $0.date < $1.date }
    }

    func fetchSleepHeartRates(sessions: [SleepSession]) async throws -> [Date: Double] {
        guard !sessions.isEmpty else { return [:] }
        let windows = sessions
            .map { SessionWindow(nightDate: $0.nightDate, start: $0.startTime, end: $0.endTime) }
            .sorted { $0.start < $1.start }
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let unit = HKUnit.count().unitDivided(by: .minute())

        // One OR of the sleep windows rather than a single predicate spanning
        // the earliest start to the latest end. The wide version pulled every
        // heart-rate sample the person had — three years of daytime and
        // workout readings, hundreds of thousands of samples — and then threw
        // nearly all of them away in memory. Chunked so no single predicate
        // grows to a thousand subpredicates.
        let chunks = stride(from: 0, to: windows.count, by: Self.heartRateWindowChunkSize).map { offset in
            Array(windows[offset..<min(offset + Self.heartRateWindowChunkSize, windows.count)])
        }

        var hrSamples: [TimedQuantitySample] = []
        for chunk in chunks {
            let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: chunk.map {
                HKQuery.predicateForSamples(withStart: $0.start, end: $0.end)
            })

            let raw: [HKSample] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: hrType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
                ) { _, result, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: result ?? []) }
                }
                store.execute(query)
            }

            hrSamples.append(contentsOf: raw.compactMap { sample -> TimedQuantitySample? in
                guard let sample = sample as? HKQuantitySample else { return nil }
                return TimedQuantitySample(
                    startDate: sample.startDate,
                    value: sample.quantity.doubleValue(for: unit)
                )
            })
        }

        return Self.averageSamplesBySession(samples: hrSamples, windows: windows)
    }

    private struct SessionWindow {
        let nightDate: Date
        let start: Date
        let end: Date
    }

    static func averageSamplesBySession(
        samples: [TimedQuantitySample],
        sessions: [SleepSession]
    ) -> [Date: Double] {
        let windows = sessions
            .map { SessionWindow(nightDate: $0.nightDate, start: $0.startTime, end: $0.endTime) }
            .sorted { $0.start < $1.start }
        return averageSamplesBySession(samples: samples, windows: windows)
    }

    private static func averageSamplesBySession(
        samples: [TimedQuantitySample],
        windows: [SessionWindow]
    ) -> [Date: Double] {
        guard !samples.isEmpty, !windows.isEmpty else { return [:] }
        let sortedSamples = samples.sorted { $0.startDate < $1.startDate }
        var result: [Date: Double] = [:]
        var sampleIndex = 0

        for window in windows {
            while sampleIndex < sortedSamples.count && sortedSamples[sampleIndex].startDate < window.start {
                sampleIndex += 1
            }

            // The cursor tracks `window.start` only, which is monotonic across
            // the sorted windows. It used to be advanced to the end of each
            // window's scan as well, so two overlapping windows — a nap and the
            // night around it — had the second one start after the first one's
            // samples and silently miss them.
            var scanIndex = sampleIndex
            var total = 0.0
            var count = 0
            while scanIndex < sortedSamples.count && sortedSamples[scanIndex].startDate < window.end {
                total += sortedSamples[scanIndex].value
                count += 1
                scanIndex += 1
            }

            if count > 0 {
                result[window.nightDate] = total / Double(count)
            }
        }

        return result
    }

    enum HealthKitError: LocalizedError {
        case notAvailable

        var errorDescription: String? {
            "Health data is not available on this device."
        }
    }
}
