import Foundation
import HealthKit

final class HealthKitManager: @unchecked Sendable {
    private let store = HKHealthStore()

    struct TimedQuantitySample {
        let startDate: Date
        let value: Double
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
        ]
        try await store.requestAuthorization(toShare: [], read: types)
    }

    func fetchAllSleepSamples() async throws -> [SleepSession] {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: nil,
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

        let categorySamples = samples.compactMap { $0 as? HKCategorySample }
        return Self.groupIntoSessions(categorySamples, movementSamples: [])
    }

    func enrichSessionsWithMovement(_ sessions: [SleepSession]) async throws -> [SleepSession] {
        var enriched: [SleepSession] = []
        enriched.reserveCapacity(sessions.count)

        for session in sessions {
            async let movementSamples = fetchMovementSamples(
                in: AwakeEventDetector.movementEvidenceWindows(for: session)
            )
            async let standSamples = fetchStandHourSamples(
                in: AwakeEventDetector.standEvidenceWindow(for: session)
            )
            enriched.append(
                SleepSession(
                    copying: session,
                    movementSamples: try await movementSamples + standSamples
                )
            )
        }

        return enriched
    }

    private func fetchMovementSamples(in windows: [DateInterval]) async throws -> [MovementSample] {
        var samples: [MovementSample] = []
        samples.reserveCapacity(windows.count)

        for window in windows {
            async let steps = fetchCumulativeQuantity(
                identifier: .stepCount,
                unit: .count(),
                start: window.start,
                end: window.end
            )
            async let distance = fetchCumulativeQuantity(
                identifier: .distanceWalkingRunning,
                unit: .meter(),
                start: window.start,
                end: window.end
            )

            let movement = try await MovementSample(
                startDate: window.start,
                endDate: window.end,
                stepCount: steps,
                distance: distance,
                sourceName: "HealthKit"
            )
            if movement.stepCount > 0 || movement.distance > 0 {
                samples.append(movement)
            }
        }

        return samples
    }

    private func fetchStandHourSamples(in window: DateInterval?) async throws -> [MovementSample] {
        guard let window else { return [] }

        let standType = HKObjectType.categoryType(forIdentifier: .appleStandHour)!
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end)
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
        _ samples: [HKCategorySample],
        movementSamples: [MovementSample]
    ) -> [SleepSession] {
        let calendar = Calendar.current
        var sessionMap: [Date: [SleepStage]] = [:]

        for sample in samples {
            guard let stageType = SleepStageType.from(sample.value) else { continue }

            // Assign to a night using noon-to-noon window:
            // samples before noon belong to the current calendar day (the morning of that night),
            // samples at/after noon belong to the next calendar day.
            let midpoint = Date(timeIntervalSince1970:
                (sample.startDate.timeIntervalSince1970 + sample.endDate.timeIntervalSince1970) / 2)
            let hour = calendar.component(.hour, from: midpoint)
            let morningDate: Date
            if hour < 12 {
                morningDate = calendar.startOfDay(for: midpoint)
            } else {
                let nextDay = calendar.date(byAdding: .day, value: 1, to: midpoint)!
                morningDate = calendar.startOfDay(for: nextDay)
            }

            let stage = SleepStage(
                id: sample.uuid,
                startDate: sample.startDate,
                endDate: sample.endDate,
                type: stageType,
                sourceName: sample.sourceRevision.source.name,
                healthKitUUID: sample.uuid
            )
            sessionMap[morningDate, default: []].append(stage)
        }

        return sessionMap.map { date, stages in
            let start = stages.map(\.startDate).min() ?? date
            let end = stages.map(\.endDate).max() ?? date
            let movements = movementSamples.filter { $0.startDate < end.addingTimeInterval(5 * 60) && $0.endDate > start.addingTimeInterval(-2 * 60) }
            return SleepSession(
                nightDate: date,
                stages: stages.sorted { $0.startDate < $1.startDate },
                movementSamples: movements
            )
        }.sorted { $0.nightDate > $1.nightDate }
    }

    func fetchDailyCalories(start: Date, end: Date) async throws -> [DailyMetricSample] {
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
        return byDay
            .map { DailyMetricSample(date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
    }

    func fetchDailyMetrics(
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
        let start = windows.map(\.start).min()!
        let end = windows.map(\.end).max()!
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let unit = HKUnit.count().unitDivided(by: .minute())

        let raw: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result ?? []) }
            }
            store.execute(query)
        }

        let hrSamples = raw.compactMap { sample -> TimedQuantitySample? in
            guard let sample = sample as? HKQuantitySample else { return nil }
            return TimedQuantitySample(
                startDate: sample.startDate,
                value: sample.quantity.doubleValue(for: unit)
            )
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

            var scanIndex = sampleIndex
            var total = 0.0
            var count = 0
            while scanIndex < sortedSamples.count && sortedSamples[scanIndex].startDate < window.end {
                total += sortedSamples[scanIndex].value
                count += 1
                scanIndex += 1
            }
            sampleIndex = scanIndex

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
