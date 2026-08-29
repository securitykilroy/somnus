import SwiftUI

struct MeditationToSleepView: View {
    let sessions: [SleepSession]
    let dailyMindfulMinutes: [DailyMetricSample]
    let recoveryScores: [RecoveryScore]

    private struct Pairing {
        let minutes: Double
        let session: SleepSession
        let recoveryScore: Double?
    }

    private var pairings: [Pairing] {
        let minutesByDay = Dictionary(
            dailyMindfulMinutes.map { (Calendar.current.startOfDay(for: $0.date), $0.value) },
            uniquingKeysWith: { $1 }
        )
        let scoresByNight = Dictionary(
            recoveryScores.map { (Calendar.current.startOfDay(for: $0.date), $0.score) },
            uniquingKeysWith: { $1 }
        )
        return sessions.compactMap { session in
            let activityDay = Calendar.current.date(byAdding: .day, value: -1, to: session.nightDate)!
            guard let minutes = minutesByDay[Calendar.current.startOfDay(for: activityDay)],
                  minutes > 0 else { return nil }
            let score = scoresByNight[Calendar.current.startOfDay(for: session.nightDate)]
            return Pairing(minutes: minutes, session: session, recoveryScore: score)
        }
    }

    var body: some View {
        let pairs = pairings
        let scoredPairs = pairs.filter { $0.recoveryScore != nil }

        VStack(alignment: .leading, spacing: 8) {
            Text("Meditation vs Sleep & Recovery")
                .font(.headline)
            Text("Minutes meditated on day N vs the stage makeup, recovery, of sleep that night")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if pairs.isEmpty {
                Text("No paired meditation and sleep data available — requires Mindful Minutes in Health")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                MetricScatterChartView(
                    title: "Deep Sleep %",
                    points: pairs.map { (x: $0.minutes, y: $0.session.deepRatio * 100) },
                    color: .indigo,
                    xAxisLabel: "Minutes Meditated",
                    yAxisLabel: "Deep %",
                    interpretation: { $0 >= 0 ? "more meditation → more deep sleep" : "more meditation → less deep sleep" }
                )

                MetricScatterChartView(
                    title: "REM Sleep %",
                    points: pairs.map { (x: $0.minutes, y: $0.session.remRatio * 100) },
                    color: .teal,
                    xAxisLabel: "Minutes Meditated",
                    yAxisLabel: "REM %",
                    interpretation: { $0 >= 0 ? "more meditation → more REM sleep" : "more meditation → less REM sleep" }
                )

                MetricScatterChartView(
                    title: "Recovery Score",
                    points: scoredPairs.map { (x: $0.minutes, y: $0.recoveryScore!) },
                    color: .green,
                    xAxisLabel: "Minutes Meditated",
                    yAxisLabel: "Recovery",
                    interpretation: { $0 >= 0 ? "more meditation → higher next-day recovery" : "more meditation → lower next-day recovery" }
                )
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
