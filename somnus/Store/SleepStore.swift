import Foundation
import HealthKit
import Observation

@MainActor
@Observable
final class SleepStore {
    var sessions: [SleepSession] = []
    var isLoading = false
    var error: Error?

    var dailyCalories: [DailyMetricSample] = []
    var dailyRestingHR: [DailyMetricSample] = []
    var dailyHRV: [DailyMetricSample] = []
    var sleepHeartRates: [Date: Double] = [:]

    private let healthKit = HealthKitManager()

    var lastNight: SleepSession? { sessions.first }

    var trendSummary: SleepTrendSummary {
        SleepTrendSummary(sessions: sessions, targetSleep: 8 * 3600)
    }

    var lifetimeMean: TimeInterval {
        guard !sessions.isEmpty else { return 0 }
        return sessions.reduce(0.0) { $0 + $1.totalSleep } / Double(sessions.count)
    }

    var lifetimeMedian: TimeInterval {
        guard !sessions.isEmpty else { return 0 }
        let sorted = sessions.map(\.totalSleep).sorted()
        let count = sorted.count
        return count % 2 == 0
            ? (sorted[count / 2 - 1] + sorted[count / 2]) / 2
            : sorted[count / 2]
    }

    func sessions(in range: ClosedRange<Date>) -> [SleepSession] {
        sessions.filter { range.contains($0.nightDate) }
    }

    static func metricsFetchWindow(
        for sessions: [SleepSession],
        end: Date = Date(),
        calendar: Calendar = .current
    ) -> DateInterval {
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: end)!
        let oldestSessionStart = sessions.map(\.startTime).min()
        let start = oldestSessionStart.map { Swift.max($0, oneYearAgo) } ?? oneYearAgo
        return DateInterval(start: start, end: end)
    }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            try await healthKit.requestAuthorization()
            let fetched = try await healthKit.fetchAllSleepSamples()
            sessions = fetched
            Task { await loadMovementEvidence(for: fetched) }
            Task { await loadMetrics(for: fetched) }
        } catch {
            self.error = error
        }
    }

    private func loadMovementEvidence(for fetched: [SleepSession]) async {
        let window = Self.metricsFetchWindow(for: fetched)
        let sessionsToEnrich = fetched.filter { window.contains($0.nightDate) }
        guard let enriched = try? await healthKit.enrichSessionsWithMovement(sessionsToEnrich) else { return }
        let enrichedByDate = Dictionary(uniqueKeysWithValues: enriched.map { ($0.nightDate, $0) })

        let currentDates = sessions.map(\.nightDate)
        guard currentDates == fetched.map(\.nightDate) else { return }
        sessions = sessions.map { enrichedByDate[$0.nightDate] ?? $0 }
    }

    private func loadMetrics(for fetched: [SleepSession]) async {
        let window = Self.metricsFetchWindow(for: fetched)
        let sessionsForMetrics = fetched.filter { window.contains($0.nightDate) }

        async let cals    = healthKit.fetchDailyCalories(start: window.start, end: window.end)
        async let rhr     = healthKit.fetchDailyMetrics(identifier: .restingHeartRate,
                                                        unit: .count().unitDivided(by: .minute()),
                                                        start: window.start, end: window.end)
        async let hrv     = healthKit.fetchDailyMetrics(identifier: .heartRateVariabilitySDNN,
                                                        unit: .secondUnit(with: .milli),
                                                        start: window.start, end: window.end)
        async let sleepHR = healthKit.fetchSleepHeartRates(sessions: sessionsForMetrics)

        dailyCalories   = (try? await cals)    ?? []
        dailyRestingHR  = (try? await rhr)     ?? []
        dailyHRV        = (try? await hrv)     ?? []
        sleepHeartRates = (try? await sleepHR) ?? [:]
    }
}
