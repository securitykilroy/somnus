import Foundation

struct SleepOutlier: Identifiable {
    let id = UUID()
    let session: SleepSession
    let metric: String
    let value: TimeInterval
    let baseline: TimeInterval
    let deviation: TimeInterval
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
              !weekday.isEmpty, !weekend.isEmpty else { return 0 }
        return abs(meanMidpoint(weekday) - meanMidpoint(weekend))
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

    private func meanMidpoint(_ values: [SleepSession]) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        let seconds = values.map { secondsSinceStartOfDay($0.regularityAnchor) }
        return seconds.reduce(0, +) / Double(seconds.count)
    }

    private func circularTimeVariability(_ dates: [Date]) -> TimeInterval {
        guard dates.count > 1 else { return 0 }
        let seconds = dates.map(secondsSinceStartOfDay)
        let mean = seconds.reduce(0, +) / Double(seconds.count)
        let variance = seconds.reduce(0) { partial, value in
            let delta = min(abs(value - mean), 86400 - abs(value - mean))
            return partial + (delta * delta)
        } / Double(seconds.count)
        return sqrt(variance)
    }

    private func secondsSinceStartOfDay(_ date: Date) -> TimeInterval {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return TimeInterval((components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60 + (components.second ?? 0))
    }
}
