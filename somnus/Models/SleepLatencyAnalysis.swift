import Foundation

struct SleepLatencyRecord: Identifiable, Hashable {
    let sessionID: UUID
    let nightDate: Date
    let intentTime: Date
    let firstSleepTime: Date
    let latency: TimeInterval
    let intentEventID: UUID
    let appleLatency: TimeInterval

    var id: String {
        "\(sessionID.uuidString)-\(intentEventID.uuidString)"
    }

    var appleLatencyDelta: TimeInterval {
        latency - appleLatency
    }

    var hasAppleLatencyMismatch: Bool {
        appleLatency > 0 && abs(appleLatencyDelta) >= 20 * 60
    }

    var latencyBand: SleepLatencyBand {
        SleepLatencyBand(latency: latency)
    }
}

enum SleepLatencyBand: String {
    case quick = "Quick"
    case typical = "Typical"
    case long = "Long"
    case veryLong = "Very Long"

    init(latency: TimeInterval) {
        switch latency {
        case ..<(15 * 60):
            self = .quick
        case ..<(35 * 60):
            self = .typical
        case ..<(75 * 60):
            self = .long
        default:
            self = .veryLong
        }
    }
}

struct SleepLatencyOutlier: Identifiable, Hashable {
    let record: SleepLatencyRecord
    let baseline: TimeInterval
    let deviation: TimeInterval

    var id: String { record.id }
}

struct SleepLatencySummary {
    let records: [SleepLatencyRecord]
    let latestLatency: TimeInterval?
    let sevenDayAverage: TimeInterval?
    let thirtyDayAverage: TimeInterval?
    let medianLatency: TimeInterval?
    let longestRecent: SleepLatencyRecord?
    let count: Int
    let longLatencyCount: Int
    let veryLongLatencyCount: Int
    let appleMismatchCount: Int
    let averageAppleLatencyDelta: TimeInterval?
    let outliers: [SleepLatencyOutlier]
}

struct SleepLatencySnapshot: Identifiable, Hashable, Codable {
    let id: UUID
    let nightDate: Date
    let intentTime: Date
    let firstSleepTime: Date
    let latency: TimeInterval
    let appleLatency: TimeInterval
    let createdAt: Date
    let updatedAt: Date
}

enum SleepLatencyAnalyzer {
    static let maximumLatency: TimeInterval = 6 * 3600

    static func records(
        sessions: [SleepSession],
        events: [SleepIntentEvent],
        calendar: Calendar = .current
    ) -> [SleepLatencyRecord] {
        let tryingEvents = events
            .filter { $0.kind == .tryingToSleep }
            .sorted { $0.timestamp < $1.timestamp }

        return sessions.compactMap { session in
            guard let firstSleep = session.normalizedTimeline.firstSleepStart else {
                return nil
            }

            let matchingEvent = tryingEvents
                .filter { event in
                    guard event.timestamp <= firstSleep else { return false }
                    let latency = firstSleep.timeIntervalSince(event.timestamp)
                    guard (0...maximumLatency).contains(latency) else { return false }
                    return calendar.isDate(event.timestamp, inSameDayAs: session.nightDate)
                        || latency <= maximumLatency
                }
                .max { $0.timestamp < $1.timestamp }

            guard let matchingEvent else { return nil }
            let latency = firstSleep.timeIntervalSince(matchingEvent.timestamp)

            return SleepLatencyRecord(
                sessionID: session.id,
                nightDate: session.nightDate,
                intentTime: matchingEvent.timestamp,
                firstSleepTime: firstSleep,
                latency: latency,
                intentEventID: matchingEvent.id,
                appleLatency: session.sleepLatency
            )
        }
        .sorted { $0.nightDate < $1.nightDate }
    }

    static func summary(
        records: [SleepLatencyRecord],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> SleepLatencySummary {
        let sorted = records.sorted { $0.nightDate < $1.nightDate }
        let sevenDayRecords = recentRecords(inLast: 7, from: sorted, calendar: calendar, now: now)
        let thirtyDayRecords = recentRecords(inLast: 30, from: sorted, calendar: calendar, now: now)

        return SleepLatencySummary(
            records: sorted,
            latestLatency: sorted.last?.latency,
            sevenDayAverage: averageLatency(sevenDayRecords),
            thirtyDayAverage: averageLatency(thirtyDayRecords),
            medianLatency: medianLatency(thirtyDayRecords),
            longestRecent: thirtyDayRecords.max { $0.latency < $1.latency },
            count: sorted.count,
            longLatencyCount: thirtyDayRecords.filter { $0.latencyBand == .long || $0.latencyBand == .veryLong }.count,
            veryLongLatencyCount: thirtyDayRecords.filter { $0.latencyBand == .veryLong }.count,
            appleMismatchCount: thirtyDayRecords.filter(\.hasAppleLatencyMismatch).count,
            averageAppleLatencyDelta: averageAppleLatencyDelta(thirtyDayRecords),
            outliers: outliers(in: thirtyDayRecords)
        )
    }

    private static func recentRecords(
        inLast days: Int,
        from records: [SleepLatencyRecord],
        calendar: Calendar,
        now: Date
    ) -> [SleepLatencyRecord] {
        let end = records.last?.nightDate ?? now
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else {
            return records
        }
        let window = records.filter { $0.nightDate >= start && $0.nightDate <= end }
        return Array(window.suffix(days))
    }

    private static func averageLatency(_ records: [SleepLatencyRecord]) -> TimeInterval? {
        guard !records.isEmpty else { return nil }
        return records.reduce(0) { $0 + $1.latency } / Double(records.count)
    }

    private static func medianLatency(_ records: [SleepLatencyRecord]) -> TimeInterval? {
        guard !records.isEmpty else { return nil }
        let sorted = records.map(\.latency).sorted()
        let midpoint = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[midpoint - 1] + sorted[midpoint]) / 2
        }
        return sorted[midpoint]
    }

    private static func averageAppleLatencyDelta(_ records: [SleepLatencyRecord]) -> TimeInterval? {
        let values = records.filter { $0.appleLatency > 0 }.map(\.appleLatencyDelta)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func outliers(in records: [SleepLatencyRecord]) -> [SleepLatencyOutlier] {
        guard records.count >= 4,
              let baseline = averageLatency(records) else {
            return []
        }

        let variance = records.reduce(0) { total, record in
            let delta = record.latency - baseline
            return total + delta * delta
        } / Double(records.count)
        let standardDeviation = sqrt(variance)
        let threshold = max(45 * 60, standardDeviation * 1.5)

        return records
            .filter { $0.latency > baseline + threshold }
            .map {
                SleepLatencyOutlier(
                    record: $0,
                    baseline: baseline,
                    deviation: $0.latency - baseline
                )
            }
            .sorted { $0.record.latency > $1.record.latency }
    }
}
