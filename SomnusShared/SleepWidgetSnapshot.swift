import Foundation

/// The stages the widget draws. Deliberately not `SleepStageType` — that type
/// pulls in HealthKit, and the widget extension should stay a pure formatter
/// with no analysis or HealthKit code linked into it.
nonisolated enum SleepWidgetStage: String, Codable, CaseIterable, Identifiable {
    case core
    case deep
    case rem
    /// Sleep a source recorded without a stage — iPhone-only tracking and some
    /// third-party writers. Kept separate so the bar still adds up to the night
    /// instead of quietly under-reporting it.
    case unspecified
    case awake

    var id: String { rawValue }

    var label: String {
        switch self {
        case .core:        return "Core"
        case .deep:        return "Deep"
        case .rem:         return "REM"
        case .unspecified: return "Asleep"
        case .awake:       return "Awake"
        }
    }
}

nonisolated struct SleepWidgetStageSlice: Codable, Hashable {
    let stage: SleepWidgetStage
    let duration: TimeInterval
    /// Share of *total sleep*, so the three sleep stages sum to 1. Awake time
    /// is not part of total sleep, so its ratio is not meaningful as a
    /// percentage and the views render only its duration.
    let ratio: Double
}

/// Everything the widget needs for one night, precomputed by the app.
///
/// The widget target does no analysis: it reads this value and formats it. That
/// keeps the extension inside WidgetKit's memory budget and means the session
/// grouping and stage math have exactly one implementation, in the app.
nonisolated struct SleepWidgetSnapshot: Codable, Hashable {
    /// Start of the morning the sleep ended, matching `SleepSession.nightDate`.
    let nightDate: Date
    let totalSleep: TimeInterval
    let timeInBed: TimeInterval
    let efficiency: Double
    let sleepLatency: TimeInterval
    let slices: [SleepWidgetStageSlice]
    let generatedAt: Date

    func slice(_ stage: SleepWidgetStage) -> SleepWidgetStageSlice? {
        slices.first { $0.stage == stage }
    }

    var rem: SleepWidgetStageSlice? { slice(.rem) }
    var deep: SleepWidgetStageSlice? { slice(.deep) }
    var core: SleepWidgetStageSlice? { slice(.core) }
    var awake: SleepWidgetStageSlice? { slice(.awake) }

    /// Total of every slice, including awake — the denominator for the stage
    /// bar, which represents the whole night rather than just time asleep.
    var chartedDuration: TimeInterval {
        slices.reduce(0) { $0 + $1.duration }
    }
}

// MARK: - Freshness

extension SleepWidgetSnapshot {
    /// `nightDate` is the morning of the night, so a snapshot covering last
    /// night carries today's date.
    func isCurrent(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.isDate(nightDate, inSameDayAs: now)
    }

    func nightsAgo(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let from = calendar.startOfDay(for: nightDate)
        let to = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    /// Header for the sizes with room for one: "Last night" when current,
    /// otherwise the night's own date so a stale widget never reads as fresh.
    func dateLabel(now: Date = Date(), calendar: Calendar = .current) -> String {
        if isCurrent(now: now, calendar: calendar) { return "Last night" }

        var formatter = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        return nightDate.formatted(formatter)
    }

    /// Compact staleness marker for the accessory sizes, which have no room for
    /// a date. `nil` when the snapshot is current.
    func stalenessBadge(now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard !isCurrent(now: now, calendar: calendar) else { return nil }
        return "\(nightsAgo(now: now, calendar: calendar))d"
    }
}

// MARK: - Sample data

extension SleepWidgetSnapshot {
    /// Used for previews, the widget gallery, and the placeholder shown while
    /// WidgetKit waits on a real timeline.
    static func sample(nightDate: Date = Calendar.current.startOfDay(for: Date())) -> SleepWidgetSnapshot {
        let total: TimeInterval = 7 * 3600 + 12 * 60
        return SleepWidgetSnapshot(
            nightDate: nightDate,
            totalSleep: total,
            timeInBed: total + 49 * 60,
            efficiency: 0.88,
            sleepLatency: 14 * 60,
            slices: [
                SleepWidgetStageSlice(stage: .core, duration: 3 * 3600 + 46 * 60, ratio: 0.52),
                SleepWidgetStageSlice(stage: .deep, duration: 58 * 60, ratio: 0.13),
                SleepWidgetStageSlice(stage: .rem, duration: 1 * 3600 + 34 * 60, ratio: 0.22),
                SleepWidgetStageSlice(stage: .awake, duration: 22 * 60, ratio: 0.05),
            ],
            generatedAt: nightDate
        )
    }
}
