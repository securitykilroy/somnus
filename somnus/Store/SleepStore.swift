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

            // Compute the window and filter lists here on the main actor, so the
            // detached tasks receive plain Sendable values and never need to call
            // back into actor-isolated code just to derive these.
            let hk = healthKit
            let window = Self.metricsFetchWindow(for: fetched)
            let toEnrich  = fetched.filter { window.contains($0.nightDate) }
            let forMetrics = fetched.filter { window.contains($0.nightDate) }

            // Task.detached (not Task {}) so these run on the cooperative thread
            // pool rather than inheriting @MainActor, keeping the UI responsive.
            Task.detached(priority: .utility) { [weak self] in
                guard let enriched = try? await hk.enrichSessionsWithMovement(toEnrich) else { return }
                let byDate = Dictionary(uniqueKeysWithValues: enriched.map { ($0.nightDate, $0) })
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard sessions.map(\.nightDate) == fetched.map(\.nightDate) else { return }
                    sessions = sessions.map { byDate[$0.nightDate] ?? $0 }
                }
            }
            Task.detached(priority: .utility) { [weak self] in
                async let cals    = hk.fetchDailyCalories(start: window.start, end: window.end)
                async let rhr     = hk.fetchDailyMetrics(identifier: .restingHeartRate,
                                                         unit: .count().unitDivided(by: .minute()),
                                                         start: window.start, end: window.end)
                async let hrv     = hk.fetchDailyMetrics(identifier: .heartRateVariabilitySDNN,
                                                         unit: .secondUnit(with: .milli),
                                                         start: window.start, end: window.end)
                async let sleepHR = hk.fetchSleepHeartRates(sessions: forMetrics)
                let calResult     = (try? await cals)    ?? []
                let rhrResult     = (try? await rhr)     ?? []
                let hrvResult     = (try? await hrv)     ?? []
                let sleepHRResult = (try? await sleepHR) ?? [:]
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    dailyCalories   = calResult
                    dailyRestingHR  = rhrResult
                    dailyHRV        = hrvResult
                    sleepHeartRates = sleepHRResult
                }
            }
        } catch {
            self.error = error
        }
    }
}
