import Charts
import SwiftUI

struct MorningWakeTrendView: View {
    let sessions: [SleepSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Early Morning Wake")
                .font(.headline)
            Text("Final wake tail and awake/in-bed time after 4 AM")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(sessions) { session in
                    let analysis = session.morningWakeAnalysis()

                    BarMark(
                        x: .value("Date", session.nightDate, unit: .day),
                        y: .value("Final wake tail", analysis.terminalWakeDuration.asHours)
                    )
                    .foregroundStyle(Color.orange.opacity(0.75))

                    PointMark(
                        x: .value("Date", session.nightDate, unit: .day),
                        y: .value("Awake/In Bed", analysis.awakeOrInBedAfterCutoff.asHours)
                    )
                    .foregroundStyle(Color.red)
                    .symbol(.circle)
                }
            }
            .chartYAxisLabel("Hours")
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .frame(height: 200)

            HStack(spacing: 12) {
                legendDot(.orange.opacity(0.75), "Final wake tail")
                legendDot(.red, "Awake/in bed after 4 AM")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
        }
    }
}
