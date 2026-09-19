import Foundation

struct SleepOutlier: Identifiable {
    let session: SleepSession
    let metric: String
    let value: TimeInterval
    let baseline: TimeInterval
    let deviation: TimeInterval

    var id: String {
        "\(session.id.uuidString)|\(metric)"
    }
}

struct SleepTrendSummary {
    let sessions: [SleepSession]
    let targetSleep: TimeInterval

    var sevenDaySessions: [SleepSession] { recent(days: 7) }
    var thirtyDaySessions: [SleepSession] { recent(days: 30) }
    var ninetyDaySessions: [SleepSession] { recent(days: 90) }

    var sevenDayMean: TimeInterval { meanSleep(sevenDaySessions) }
    var thirtyDayMean: TimeInterval { meanSleep(thirtyDaySessions) }
    var ninetyDayMean: TimeInterval { meanSleep(ninetyDaySessions) }

    var acuteDebt: TimeInterval {
        sevenDaySessions.reduce(0) { $0 + max(0, targetSleep - $1.totalSleep) }
    }

    var chronicDebt: TimeInterval {
        thirtyDaySessions.reduce(0) { $0 + max(0, targetSleep - $1.totalSleep) }
    }

    var averageEfficiency: Double {
        guard !sessions.isEmpty else { return 0 }
        return sessions.reduce(0) { $0 + $1.efficiency } / Double(sessions.count)
    }

    var averageFragmentation: Double {
        guard !sessions.isEmpty else { return 0 }
        return sessions.reduce(0) { $0 + $1.fragmentationIndex } / Double(sessions.count)
    }

    var totalMovementConfirmedWakeups: Int {
        sessions.reduce(0) { $0 + $1.movementConfirmedAwakeningCount }
    }

    var totalLikelyOutOfBedDuration: TimeInterval {
        sessions.reduce(0) { $0 + $1.likelyOutOfBedDuration }
    }

    var bedtimeVariability: TimeInterval {
        circularTimeVariability(sessions.map(\.startTime))
    }

    var wakeVariability: TimeInterval {
        circularTimeVariability(sessions.map(\.endTime))
    }

    var socialJetlag: TimeInterval {
        let grouped = Dictionary(grouping: sessions) { session in
            Calendar.current.isDateInWeekend(session.nightDate)
        }
        guard let weekday = grouped[false], let weekend = grouped[true],
              let weekdayMidpoint = meanMidpoint(weekday),
              let weekendMidpoint = meanMidpoint(weekend) else { return 0 }
        return Self.circularDelta(weekdayMidpoint, weekendMidpoint)
    }

    var outliers: [SleepOutlier] {
        guard sessions.count >= 5 else { return [] }
        let sorted = sessions.sorted { $0.nightDate < $1.nightDate }
        return sorted.enumerated().compactMap { index, session in
            let baselineWindow = Array(sorted[max(0, index - 7)..<index])
            let baseline = baselineWindow.isEmpty ? meanSleep(sorted) : meanSleep(baselineWindow)
            let deviation = session.totalSleep - baseline
            guard abs(deviation) >= 2 * 3600 else { return nil }
            return SleepOutlier(
                session: session,
                metric: "Sleep duration",
                value: session.totalSleep,
                baseline: baseline,
                deviation: deviation
            )
        }
    }

    func recent(days: Int) -> [SleepSession] {
        guard let latest = sessions.map(\.nightDate).max() else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: latest) ?? latest
        return sessions
            .filter { $0.nightDate >= Calendar.current.startOfDay(for: start) && $0.nightDate <= latest }
            .sorted { $0.nightDate < $1.nightDate }
    }

    private func meanSleep(_ values: [SleepSession]) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0) { $0 + $1.totalSleep } / Double(values.count)
    }

    private func meanMidpoint(_ values: [SleepSession]) -> TimeInterval? {
        Self.circularMean(values.map { secondsSinceStartOfDay($0.regularityAnchor) })
    }

    /// Spread of a set of clock times, as the root-mean-square distance from
    /// their average — measured around the 24-hour circle at both ends.
    ///
    /// The deviations were always wrapped, but the average they were measured
    /// from was a plain arithmetic mean, which is not a clock time. Bedtimes of
    /// 23:00 and 00:30 averaged to 11:45 in the morning, putting both of them
    /// roughly twelve hours from the anchor: a 1.5-hour spread reported as 9.6
    /// hours of drift. Anyone who goes to bed near midnight saw a number with
    /// no relation to how regular they actually were.
    private func circularTimeVariability(_ dates: [Date]) -> TimeInterval {
        guard dates.count > 1 else { return 0 }
        let seconds = dates.map(secondsSinceStartOfDay)
        guard let mean = Self.circularMean(seconds) else { return 0 }

        let variance = seconds.reduce(0) { partial, value in
            let delta = Self.circularDelta(value, mean)
            return partial + (delta * delta)
        } / Double(seconds.count)
        return sqrt(variance)
    }

    /// The average of clock times treated as points on a circle: average the
    /// unit vectors, then read the angle back. `nil` when the times are spread
    /// so evenly around the clock that no average is meaningful.
    static func circularMean(_ seconds: [TimeInterval]) -> TimeInterval? {
        guard !seconds.isEmpty else { return nil }

        let radiansPerSecond = 2 * Double.pi / 86_400
        var sines = 0.0
        var cosines = 0.0
        for value in seconds {
            let angle = value * radiansPerSecond
            sines += sin(angle)
            cosines += cos(angle)
        }

        let count = Double(seconds.count)
        let resultantLength = ((sines * sines) + (cosines * cosines)).squareRoot() / count
        guard resultantLength > 1e-9 else { return nil }

        let angle = atan2(sines / count, cosines / count)
        let normalized = angle < 0 ? angle + 2 * .pi : angle
        return normalized / radiansPerSecond
    }

    /// Distance between two clock times the short way round the dial, so 23:30
    /// and 00:30 are an hour apart rather than twenty-three.
    static func circularDelta(_ lhs: TimeInterval, _ rhs: TimeInterval) -> TimeInterval {
        let raw = abs(lhs - rhs)
        return min(raw, 86_400 - raw)
    }

    private func secondsSinceStartOfDay(_ date: Date) -> TimeInterval {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return TimeInterval((components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60 + (components.second ?? 0))
    }
}
