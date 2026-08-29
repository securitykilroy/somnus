import SwiftUI

struct SleepStagesToNextDayRestingHRView: View {
    let sessions: [SleepSession]
    let dailyRestingHR: [DailyMetricSample]

    private struct Pairing {
        let restingHR: Double
        let session: SleepSession
    }

    private var pairings: [Pairing] {
        let rhrByDay = Dictionary(
            dailyRestingHR.map { (Calendar.current.startOfDay(for: $0.date), $0.value) },
            uniquingKeysWith: { $1 }
        )
        return sessions.compactMap { session in
            guard let rhr = rhrByDay[Calendar.current.startOfDay(for: session.nightDate)] else { return nil }
            return Pairing(restingHR: rhr, session: session)
        }
    }

    var body: some View {
        let pairs = pairings

        VStack(alignment: .leading, spacing: 8) {
            Text("Sleep Stages vs Next-Day Resting Heart Rate")
                .font(.headline)
            Text("A lower resting heart rate the morning after often signals better cardiac recovery — see how deep sleep, REM, and fragmentation relate to it")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if pairs.isEmpty {
                Text("No resting heart rate data available — requires Apple Watch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                MetricScatterChartView(
                    title: "Deep Sleep %",
                    points: pairs.map { (x: $0.session.deepRatio * 100, y: $0.restingHR) },
                    color: .indigo,
                    xAxisLabel: "Deep %",
                    yAxisLabel: "Resting HR (bpm)",
                    interpretation: { $0 <= 0 ? "more deep sleep → lower next-day resting HR (better recovery)" : "more deep sleep → higher next-day resting HR" }
                )

                MetricScatterChartView(
                    title: "REM Sleep %",
                    points: pairs.map { (x: $0.session.remRatio * 100, y: $0.restingHR) },
                    color: .teal,
                    xAxisLabel: "REM %",
                    yAxisLabel: "Resting HR (bpm)",
                    interpretation: { $0 <= 0 ? "more REM sleep → lower next-day resting HR (better recovery)" : "more REM sleep → higher next-day resting HR" }
                )

                MetricScatterChartView(
                    title: "Fragmentation",
                    points: pairs.map { (x: $0.session.fragmentationIndex, y: $0.restingHR) },
                    color: .orange,
                    xAxisLabel: "Fragmentation",
                    yAxisLabel: "Resting HR (bpm)",
                    interpretation: { $0 >= 0 ? "more fragmented sleep → higher next-day resting HR (worse recovery)" : "more fragmented sleep → lower next-day resting HR" }
                )
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
