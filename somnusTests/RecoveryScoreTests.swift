import Foundation
import Testing
@testable import somnus

struct RecoveryScoreTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test func betterMetricsProduceHigherScore() {
        let goodNight = calendar.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let badNight = calendar.date(from: DateComponents(year: 2026, month: 5, day: 11))!
        let averageNight = calendar.date(from: DateComponents(year: 2026, month: 5, day: 12))!

        let sessions = [
            session(nightDate: goodNight, deepRatio: 0.30, fragmentation: 0.10),
            session(nightDate: badNight, deepRatio: 0.05, fragmentation: 0.60),
            session(nightDate: averageNight, deepRatio: 0.18, fragmentation: 0.35),
        ]

        let dailyHRV = [
            DailyMetricSample(date: goodNight, value: 80),
            DailyMetricSample(date: badNight, value: 30),
            DailyMetricSample(date: averageNight, value: 55),
        ]
        let dailyRestingHR = [
            DailyMetricSample(date: goodNight, value: 50),
            DailyMetricSample(date: badNight, value: 70),
            DailyMetricSample(date: averageNight, value: 60),
        ]

        let scores = RecoveryScoreCalculator.scores(sessions: sessions, dailyHRV: dailyHRV, dailyRestingHR: dailyRestingHR)
        let byDate = Dictionary(uniqueKeysWithValues: scores.map { (calendar.startOfDay(for: $0.date), $0.score) })

        #expect(byDate[goodNight]! > byDate[averageNight]!)
        #expect(byDate[averageNight]! > byDate[badNight]!)
    }

    @Test func scoresAreClampedToZeroToHundred() {
        let dates = (0..<5).map { calendar.date(byAdding: .day, value: $0, to: calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!)! }
        let sessions = dates.enumerated().map { index, date in
            session(nightDate: date, deepRatio: index == 0 ? 0.5 : 0.05, fragmentation: index == 0 ? 0.0 : 0.7)
        }
        let dailyHRV = dates.enumerated().map { index, date in DailyMetricSample(date: date, value: index == 0 ? 120 : 20) }
        let dailyRestingHR = dates.enumerated().map { index, date in DailyMetricSample(date: date, value: index == 0 ? 40 : 80) }

        let scores = RecoveryScoreCalculator.scores(sessions: sessions, dailyHRV: dailyHRV, dailyRestingHR: dailyRestingHR)

        for entry in scores {
            #expect(entry.score >= 0)
            #expect(entry.score <= 100)
        }
    }

    @Test func missingMetricsAreOmittedRatherThanPenalized() {
        let nightWithHRV = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let nightWithoutHRV = calendar.date(from: DateComponents(year: 2026, month: 5, day: 2))!
        let thirdNight = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!

        let sessions = [
            session(nightDate: nightWithHRV, deepRatio: 0.2, fragmentation: 0.3),
            session(nightDate: nightWithoutHRV, deepRatio: 0.2, fragmentation: 0.3),
            session(nightDate: thirdNight, deepRatio: 0.2, fragmentation: 0.3),
        ]
        // Only two of the three nights have HRV samples.
        let dailyHRV = [
            DailyMetricSample(date: nightWithHRV, value: 60),
            DailyMetricSample(date: thirdNight, value: 60),
        ]

        let scores = RecoveryScoreCalculator.scores(sessions: sessions, dailyHRV: dailyHRV, dailyRestingHR: [])
        let missing = scores.first { calendar.isDate($0.date, inSameDayAs: nightWithoutHRV) }!

        #expect(missing.hrv == nil)
        // Identical deep-sleep/fragmentation to its peers and no HRV penalty —
        // the score should land at the neutral baseline, not be dragged down.
        #expect(abs(missing.score - 50) < 1e-6)
    }

    @Test func emptySessionsProduceNoScores() {
        #expect(RecoveryScoreCalculator.scores(sessions: [], dailyHRV: [], dailyRestingHR: []).isEmpty)
    }

    private func session(nightDate: Date, deepRatio: Double, fragmentation: Double) -> SleepSession {
        // Build stages that yield the desired deep ratio and a fragmentation
        // index driven primarily by awakening count (see SleepSession.fragmentationIndex).
        let start = calendar.date(byAdding: .hour, value: -8, to: nightDate)!
        let totalSleep: TimeInterval = 7 * 3600
        let deepDuration = totalSleep * deepRatio
        let coreDuration = totalSleep - deepDuration
        let awakeningCount = Int((fragmentation / 0.08).rounded())

        var stages: [SleepStage] = []
        var cursor = start
        stages.append(SleepStage(startDate: cursor, endDate: cursor.addingTimeInterval(coreDuration), type: .core))
        cursor = cursor.addingTimeInterval(coreDuration)

        if awakeningCount > 0 {
            let segment = deepDuration / Double(awakeningCount)
            for _ in 0..<awakeningCount {
                stages.append(SleepStage(startDate: cursor, endDate: cursor.addingTimeInterval(segment), type: .deep))
                cursor = cursor.addingTimeInterval(segment)
                stages.append(SleepStage(startDate: cursor, endDate: cursor.addingTimeInterval(60), type: .awake))
                cursor = cursor.addingTimeInterval(60)
            }
        } else {
            stages.append(SleepStage(startDate: cursor, endDate: cursor.addingTimeInterval(deepDuration), type: .deep))
            cursor = cursor.addingTimeInterval(deepDuration)
        }

        return SleepSession(nightDate: nightDate, stages: stages)
    }
}
