import Foundation

/// One night paired with the last thing eaten before falling asleep.
struct MealSleepRecord: Identifiable, Hashable {
    let sessionID: UUID
    let nightDate: Date
    let lastMealTime: Date
    let mealLabel: String
    let sleepOnset: Date
    /// Sleep onset minus the last meal.
    let gap: TimeInterval
    let efficiency: Double
    let deepRatio: Double
    let remRatio: Double
    let totalSleep: TimeInterval
    let awakeDuration: TimeInterval

    var id: UUID { sessionID }

    var gapHours: Double { gap / 3600 }
}

/// How nights that followed a late meal compare with nights that did not.
///
/// A mean-vs-mean split rather than only a correlation coefficient: with a few
/// weeks of entries the sample is too small for r to say much, but "your six
/// late-meal nights averaged 4% lower efficiency" is still readable.
struct MealSleepSummary {
    let lateNights: [MealSleepRecord]
    let earlyNights: [MealSleepRecord]
    let threshold: TimeInterval

    var thresholdHours: Double { threshold / 3600 }

    var hasComparison: Bool {
        lateNights.count >= 2 && earlyNights.count >= 2
    }

    var lateEfficiency: Double { Self.mean(lateNights.map(\.efficiency)) }
    var earlyEfficiency: Double { Self.mean(earlyNights.map(\.efficiency)) }
    var lateDeepRatio: Double { Self.mean(lateNights.map(\.deepRatio)) }
    var earlyDeepRatio: Double { Self.mean(earlyNights.map(\.deepRatio)) }
    var lateTotalSleep: TimeInterval { Self.mean(lateNights.map(\.totalSleep)) }
    var earlyTotalSleep: TimeInterval { Self.mean(earlyNights.map(\.totalSleep)) }
    var lateAwake: TimeInterval { Self.mean(lateNights.map(\.awakeDuration)) }
    var earlyAwake: TimeInterval { Self.mean(earlyNights.map(\.awakeDuration)) }

    var medianGap: TimeInterval? {
        let gaps = (lateNights + earlyNights).map(\.gap).sorted()
        guard !gaps.isEmpty else { return nil }
        let middle = gaps.count / 2
        return gaps.count.isMultiple(of: 2)
            ? (gaps[middle - 1] + gaps[middle]) / 2
            : gaps[middle]
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

enum MealSleepAnalyzer {
    /// Beyond this, the "last meal" is almost certainly the previous day's
    /// dinner rather than anything to do with tonight — an unlogged day would
    /// otherwise produce a 30-hour gap and drag every regression with it.
    static let maximumGap: TimeInterval = 14 * 3600

    /// Nights whose last meal fell inside this window count as late eating.
    static let defaultLateThreshold: TimeInterval = 3 * 3600

    static func records(
        sessions: [SleepSession],
        meals: [MealEvent]
    ) -> [MealSleepRecord] {
        let mealsOldestFirst = meals.sorted { $0.timestamp < $1.timestamp }

        return sessions.compactMap { session -> MealSleepRecord? in
            guard let onset = session.normalizedTimeline.firstSleepStart else { return nil }

            guard let lastMeal = mealsOldestFirst.last(where: { meal in
                let gap = onset.timeIntervalSince(meal.timestamp)
                return (0...maximumGap).contains(gap)
            }) else { return nil }

            return MealSleepRecord(
                sessionID: session.id,
                nightDate: session.nightDate,
                lastMealTime: lastMeal.timestamp,
                mealLabel: lastMeal.displayLabel,
                sleepOnset: onset,
                gap: onset.timeIntervalSince(lastMeal.timestamp),
                efficiency: session.efficiency,
                deepRatio: session.deepRatio,
                remRatio: session.remRatio,
                totalSleep: session.totalSleep,
                awakeDuration: session.awakeDuration
            )
        }
        .sorted { $0.nightDate < $1.nightDate }
    }

    static func summary(
        records: [MealSleepRecord],
        lateThreshold: TimeInterval = defaultLateThreshold
    ) -> MealSleepSummary {
        MealSleepSummary(
            lateNights: records.filter { $0.gap < lateThreshold },
            earlyNights: records.filter { $0.gap >= lateThreshold },
            threshold: lateThreshold
        )
    }
}

extension MealSleepAnalyzer {
    /// Everything eaten "for" a given night: from the start of the previous
    /// calendar day up to the moment sleep began.
    ///
    /// The window runs to sleep onset rather than to midnight so a late-night
    /// snack at 00:30 counts toward the night it actually preceded, not the
    /// next one. It opens at the start of the previous day because `nightDate`
    /// is the morning you woke — the eating that could have affected the night
    /// happened the day before.
    static func meals(
        precedingSleepIn session: SleepSession,
        from meals: [MealEvent],
        calendar: Calendar = .current
    ) -> [MealEvent] {
        let onset = session.normalizedTimeline.firstSleepStart ?? session.startTime
        guard let eatingDay = calendar.date(byAdding: .day, value: -1, to: session.nightDate) else {
            return []
        }
        let windowStart = calendar.startOfDay(for: eatingDay)

        return meals
            .filter { $0.timestamp >= windowStart && $0.timestamp < onset }
            .sorted { $0.timestamp < $1.timestamp }
    }
}
