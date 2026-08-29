import SwiftUI

struct PeakAlphaCorrelationView: View {
    let entries: [PeakAlphaEntry]
    let sessions: [SleepSession]
    let dailyMindfulMinutes: [DailyMetricSample]
    let recoveryScores: [RecoveryScore]

    private struct Pairing {
        let peakAlpha: Double
        let session: SleepSession?
        let recoveryScore: Double?
        let minutes: Double?
    }

    private var pairings: [Pairing] {
        let sessionsByDay = Dictionary(
            sessions.map { (Calendar.current.startOfDay(for: $0.nightDate), $0) },
            uniquingKeysWith: { $1 }
        )
        let scoresByDay = Dictionary(
            recoveryScores.map { (Calendar.current.startOfDay(for: $0.date), $0.score) },
            uniquingKeysWith: { $1 }
        )
        let minutesByDay = Dictionary(
            dailyMindfulMinutes.map { (Calendar.current.startOfDay(for: $0.date), $0.value) },
            uniquingKeysWith: { $1 }
        )
        return entries.map { entry in
            Pairing(
                peakAlpha: entry.value,
                session: sessionsByDay[entry.day],
                recoveryScore: scoresByDay[entry.day],
                minutes: minutesByDay[entry.day]
            )
        }
    }

    var body: some View {
        let pairs = pairings
        let recoveryPairs = pairs.compactMap { p -> (x: Double, y: Double)? in
            guard let score = p.recoveryScore else { return nil }
            return (x: score, y: p.peakAlpha)
        }
        let deepPairs = pairs.compactMap { p -> (x: Double, y: Double)? in
            guard let session = p.session else { return nil }
            return (x: session.deepRatio * 100, y: p.peakAlpha)
        }
        let meditationPairs = pairs.compactMap { p -> (x: Double, y: Double)? in
            guard let minutes = p.minutes, minutes > 0 else { return nil }
            return (x: minutes, y: p.peakAlpha)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Peak Alpha vs Sleep & Meditation")
                .font(.headline)
            Text("Your logged Peak Alpha readings vs that morning's recovery, the prior night's deep sleep, and same-day meditation")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if pairs.isEmpty {
                Text("Log Peak Alpha readings above to see how they relate to your sleep and recovery")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                MetricScatterChartView(
                    title: "Recovery Score",
                    points: recoveryPairs,
                    color: .green,
                    xAxisLabel: "Recovery",
                    yAxisLabel: "Peak Alpha",
                    interpretation: { $0 >= 0 ? "higher recovery → higher Peak Alpha" : "higher recovery → lower Peak Alpha" }
                )

                MetricScatterChartView(
                    title: "Prior Night's Deep Sleep %",
                    points: deepPairs,
                    color: .indigo,
                    xAxisLabel: "Deep %",
                    yAxisLabel: "Peak Alpha",
                    interpretation: { $0 >= 0 ? "more deep sleep → higher Peak Alpha" : "more deep sleep → lower Peak Alpha" }
                )

                MetricScatterChartView(
                    title: "Same-Day Meditation",
                    points: meditationPairs,
                    color: .purple,
                    xAxisLabel: "Minutes Meditated",
                    yAxisLabel: "Peak Alpha",
                    interpretation: { $0 >= 0 ? "more meditation → higher Peak Alpha" : "more meditation → lower Peak Alpha" }
                )
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
