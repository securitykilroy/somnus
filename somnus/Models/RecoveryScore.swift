import Foundation

struct RecoveryScore: Identifiable {
    let date: Date
    let score: Double
    let hrv: Double?
    let restingHR: Double?
    let deepRatio: Double
    let fragmentationIndex: Double

    var id: Date { date }

    var label: String {
        switch score {
        case 80...:   return "Well recovered"
        case 60..<80: return "Good recovery"
        case 40..<60: return "Average recovery"
        case 20..<40: return "Below average recovery"
        default:      return "Poor recovery"
        }
    }
}

/// Computes a relative, per-night recovery score (0-100, centered on 50) by
/// comparing HRV, resting heart rate, deep sleep %, and fragmentation against
/// the person's own baseline (mean/standard deviation across the supplied
/// sessions). Higher HRV, lower resting HR, more deep sleep, and less
/// fragmentation each push the score up; metrics with no data for a given
/// night (e.g. no Watch HRV) are simply omitted from that night's average.
enum RecoveryScoreCalculator {
    static func scores(
        sessions: [SleepSession],
        dailyHRV: [DailyMetricSample],
        dailyRestingHR: [DailyMetricSample]
    ) -> [RecoveryScore] {
        guard !sessions.isEmpty else { return [] }

        let hrvByDay = Dictionary(
            dailyHRV.map { (Calendar.current.startOfDay(for: $0.date), $0.value) },
            uniquingKeysWith: { $1 }
        )
        let rhrByDay = Dictionary(
            dailyRestingHR.map { (Calendar.current.startOfDay(for: $0.date), $0.value) },
            uniquingKeysWith: { $1 }
        )

        let entries = sessions.map { session -> (session: SleepSession, hrv: Double?, restingHR: Double?) in
            let day = Calendar.current.startOfDay(for: session.nightDate)
            return (session, hrvByDay[day], rhrByDay[day])
        }

        let hrvStats = Statistics(entries.compactMap(\.hrv))
        let rhrStats = Statistics(entries.compactMap(\.restingHR))
        let deepStats = Statistics(entries.map(\.session.deepRatio))
        let fragStats = Statistics(entries.map(\.session.fragmentationIndex))

        return entries.map { entry in
            var components: [Double] = []
            if let hrv = entry.hrv, let stats = hrvStats, let z = stats.zScore(hrv) {
                components.append(z) // higher HRV = better
            }
            if let rhr = entry.restingHR, let stats = rhrStats, let z = stats.zScore(rhr) {
                components.append(-z) // lower resting HR = better
            }
            if let stats = deepStats, let z = stats.zScore(entry.session.deepRatio) {
                components.append(z) // more deep sleep = better
            }
            if let stats = fragStats, let z = stats.zScore(entry.session.fragmentationIndex) {
                components.append(-z) // less fragmentation = better
            }

            let averageZ = components.isEmpty ? 0 : components.reduce(0, +) / Double(components.count)
            let score = max(0, min(100, 50 + averageZ * 15))

            return RecoveryScore(
                date: entry.session.nightDate,
                score: score,
                hrv: entry.hrv,
                restingHR: entry.restingHR,
                deepRatio: entry.session.deepRatio,
                fragmentationIndex: entry.session.fragmentationIndex
            )
        }
    }

    private struct Statistics {
        let mean: Double
        let standardDeviation: Double

        init?(_ values: [Double]) {
            guard values.count >= 2 else { return nil }
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
            self.mean = mean
            self.standardDeviation = variance.squareRoot()
        }

        func zScore(_ value: Double) -> Double? {
            guard standardDeviation > 1e-9 else { return nil }
            return (value - mean) / standardDeviation
        }
    }
}
