import SwiftUI

struct SleepStagesToNextDayHRVView: View {
    let sessions: [SleepSession]
    let dailyHRV: [DailyMetricSample]

    private struct Pairing {
        let hrv: Double
        let session: SleepSession
    }

    private var pairings: [Pairing] {
        let hrvByDay = Dictionary(
            dailyHRV.map { (Calendar.current.startOfDay(for: $0.date), $0.value) },
            uniquingKeysWith: { $1 }
        )
        return sessions.compactMap { session in
            guard let hrv = hrvByDay[Calendar.current.startOfDay(for: session.nightDate)] else { return nil }
            return Pairing(hrv: hrv, session: session)
        }
    }

    var body: some View {
        let pairs = pairings

        VStack(alignment: .leading, spacing: 8) {
            Text("Sleep Stages vs Next-Day HRV")
                .font(.headline)
            Text("Stage composition of last night's sleep vs HRV the following morning")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if pairs.isEmpty {
                Text("No HRV data available — requires Apple Watch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                MetricScatterChartView(
                    title: "Deep Sleep %",
                    points: pairs.map { (x: $0.session.deepRatio * 100, y: $0.hrv) },
                    color: .indigo,
                    xAxisLabel: "Deep %",
                    yAxisLabel: "HRV (ms)",
                    interpretation: { $0 >= 0 ? "more deep sleep → higher next-day HRV" : "more deep sleep → lower next-day HRV" }
                )

                MetricScatterChartView(
                    title: "REM Sleep %",
                    points: pairs.map { (x: $0.session.remRatio * 100, y: $0.hrv) },
                    color: .teal,
                    xAxisLabel: "REM %",
                    yAxisLabel: "HRV (ms)",
                    interpretation: { $0 >= 0 ? "more REM sleep → higher next-day HRV" : "more REM sleep → lower next-day HRV" }
                )

                MetricScatterChartView(
                    title: "Fragmentation",
                    points: pairs.map { (x: $0.session.fragmentationIndex, y: $0.hrv) },
                    color: .orange,
                    xAxisLabel: "Fragmentation",
                    yAxisLabel: "HRV (ms)",
                    interpretation: { $0 >= 0 ? "more fragmented sleep → higher next-day HRV" : "more fragmented sleep → lower next-day HRV" }
                )
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
