import Foundation
import HealthKit
import Observation
import WidgetKit

@MainActor
@Observable
final class SleepStore {
    /// One store per process, so the app delegate can start HealthKit
    /// observation at launch and the scene can bind to the same instance.
    static let shared = SleepStore()

    static let maximumMetricsHistoryYears = 3

    /// How long a load stays "fresh" enough to skip a foreground refresh. Long
    /// enough that flicking through Control Center does not refetch the whole
    /// history, short enough that a real return to the app does.
    /// `nonisolated` so it can be used as a default argument, which Swift
    /// evaluates outside the actor.
    nonisolated static let foregroundRefreshInterval: TimeInterval = 60

    var sessions: [SleepSession] = []
    var isLoading = false
    var error: Error?
    private(set) var dataWarnings: [String] = []

    /// When the last successful load finished. Views observe this to react to
    /// reloads they did not trigger themselves, such as observer-driven ones.
    private(set) var lastLoadedAt: Date?

    var dailyCalories: [DailyMetricSample] = []
    var dailyRestingHR: [DailyMetricSample] = []
    var dailyHRV: [DailyMetricSample] = []
    var dailyMindfulMinutes: [DailyMetricSample] = []
    var sleepHeartRates: [Date: Double] = [:]

    /// Recomputed once per load rather than inside a view body.
    ///
    /// The Overview card read `RecoveryScoreCalculator.scores(...).first`, and
    /// because the score is a z-score against the person's own baseline that
    /// call rebuilt the baseline over every night in the history — on every
    /// render, to show one number.
    private(set) var recoveryScores: [RecoveryScore] = []

    var lastNightRecoveryScore: RecoveryScore? { recoveryScores.first }

    private let healthKit = HealthKitManager()
    private let widgetSnapshots = SleepWidgetSnapshotStore()
    private var loadTask: Task<Void, Never>?
    private var enrichmentTask: Task<Void, Never>?
    private var loadRevision = 0
    private var isObservingSleepChanges = false

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
        let earliestAllowedStart = calendar.date(
            byAdding: .year,
            value: -maximumMetricsHistoryYears,
            to: end
        )!
        let oldestSessionStart = sessions.map(\.startTime).min()
        let start = oldestSessionStart.map { Swift.max($0, earliestAllowedStart) } ?? earliestAllowedStart
        return DateInterval(start: start, end: end)
    }

    static func shouldReload(
        lastLoadedAt: Date?,
        now: Date = Date(),
        minimumInterval: TimeInterval = foregroundRefreshInterval
    ) -> Bool {
        guard let lastLoadedAt else { return true }
        // A clock that moved backwards (time zone edit, manual clock change)
        // should not pin the store into a stale state.
        let elapsed = now.timeIntervalSince(lastLoadedAt)
        return elapsed < 0 || elapsed >= minimumInterval
    }

    nonisolated static func shouldApplyEnrichment(
        revision: Int,
        currentRevision: Int,
        currentNightDates: [Date],
        fetchedNightDates: [Date]
    ) -> Bool {
        revision == currentRevision && currentNightDates == fetchedNightDates
    }

    nonisolated static func resolveRefresh<Value: Sendable>(
        _ result: Result<Value, Error>,
        preserving previous: Value
    ) -> (value: Value, error: Error?) {
        switch result {
        case .success(let value): return (value, nil)
        case .failure(let error): return (previous, error)
        }
    }

    nonisolated private static func capture<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async -> Result<Value, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    /// Starts watching HealthKit for newly written sleep samples so a night that
    /// syncs from the watch after launch shows up without user action.
    func startObservingSleepChanges() {
        guard !isObservingSleepChanges else { return }
        isObservingSleepChanges = true

        let healthKit = self.healthKit
        let reload: @MainActor @Sendable () async -> Void = { [weak self] in
            await self?.load()
        }
        Task {
            await healthKit.startObservingSleepChanges {
                await reload()
            }
        }
    }

    /// Reloads only if the last load is older than `minimumInterval`. Used on
    /// foreground, where transient `.active` transitions (Control Center,
    /// notification banners) would otherwise refetch the whole history.
    func refreshIfStale(
        now: Date = Date(),
        minimumInterval: TimeInterval = foregroundRefreshInterval
    ) async {
        guard Self.shouldReload(lastLoadedAt: lastLoadedAt, now: now, minimumInterval: minimumInterval) else {
            return
        }
        await load()
    }

    /// Concurrent callers (foreground refresh, observer, pull-to-refresh) join
    /// the in-flight load rather than each kicking off a full-history refetch.
    func load() async {
        if let loadTask {
            await loadTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await performLoad()
        }
        loadTask = task
        await task.value
        if loadTask == task {
            loadTask = nil
        }
    }

    private func performLoad() async {
        isLoading = true
        error = nil
        dataWarnings = []
        loadRevision += 1
        let revision = loadRevision
        enrichmentTask?.cancel()
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
            let inWindow = fetched.filter { window.contains($0.nightDate) }

            // Task.detached (not Task {}) so these run on the cooperative thread
            // pool rather than inheriting @MainActor, keeping the UI responsive.
            enrichmentTask = Task.detached(priority: .utility) { [weak self] in
                guard let enriched = try? await hk.enrichSessionsWithMovement(inWindow) else { return }
                guard !Task.isCancelled else { return }
                let byDate = Dictionary(uniqueKeysWithValues: enriched.map { ($0.nightDate, $0) })
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard Self.shouldApplyEnrichment(
                        revision: revision,
                        currentRevision: loadRevision,
                        currentNightDates: sessions.map(\.nightDate),
                        fetchedNightDates: fetched.map(\.nightDate)
                    ) else { return }
                    sessions = sessions.map { byDate[$0.nightDate] ?? $0 }
                }
            }

            async let cals = Self.capture {
                try await hk.fetchDailyCalories(start: window.start, end: window.end)
            }
            async let rhr = Self.capture {
                try await hk.fetchDailyMetrics(
                    identifier: .restingHeartRate,
                    unit: .count().unitDivided(by: .minute()),
                    start: window.start,
                    end: window.end
                )
            }
            async let hrv = Self.capture {
                try await hk.fetchDailyMetrics(
                    identifier: .heartRateVariabilitySDNN,
                    unit: .secondUnit(with: .milli),
                    start: window.start,
                    end: window.end
                )
            }
            async let sleepHR = Self.capture {
                try await hk.fetchSleepHeartRates(sessions: inWindow)
            }
            async let mindful = Self.capture {
                try await hk.fetchDailyMindfulMinutes(start: window.start, end: window.end)
            }

            let calorieRefresh = Self.resolveRefresh(await cals, preserving: dailyCalories)
            let restingHRRefresh = Self.resolveRefresh(await rhr, preserving: dailyRestingHR)
            let hrvRefresh = Self.resolveRefresh(await hrv, preserving: dailyHRV)
            let sleepHRRefresh = Self.resolveRefresh(await sleepHR, preserving: sleepHeartRates)
            let mindfulRefresh = Self.resolveRefresh(await mindful, preserving: dailyMindfulMinutes)
            dailyCalories = calorieRefresh.value
            dailyRestingHR = restingHRRefresh.value
            dailyHRV = hrvRefresh.value
            sleepHeartRates = sleepHRRefresh.value
            dailyMindfulMinutes = mindfulRefresh.value
            dataWarnings = [
                ("Active energy", calorieRefresh.error),
                ("Resting heart rate", restingHRRefresh.error),
                ("Heart-rate variability", hrvRefresh.error),
                ("Sleep heart rate", sleepHRRefresh.error),
                ("Mindfulness", mindfulRefresh.error),
            ].compactMap { name, error in
                error.map { "\(name): \($0.localizedDescription)" }
            }
            recoveryScores = RecoveryScoreCalculator.scores(
                sessions: sessions,
                dailyHRV: dailyHRV,
                dailyRestingHR: dailyRestingHR
            )
            lastLoadedAt = Date()
            publishWidgetSnapshot()
        } catch {
            self.error = error
        }
    }

    /// Hands the newest night to the widget extension. Called on every
    /// successful load, including the background ones the HealthKit observer
    /// triggers, so the widget refreshes when the night syncs rather than
    /// waiting for the app to be opened.
    private func publishWidgetSnapshot() {
        guard let latest = sessions.first else { return }
        widgetSnapshots.write(SleepWidgetSnapshot(session: latest))
        WidgetCenter.shared.reloadAllTimelines()
    }
}
