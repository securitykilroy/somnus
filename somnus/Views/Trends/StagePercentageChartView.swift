import SwiftUI
import Charts

struct StagePercentageChartView: View {
    let sessions: [SleepSession]

    private struct Entry: Identifiable {
        let date: Date
        let type: SleepStageType
        let percent: Double

        var id: String {
            "\(date.timeIntervalSinceReferenceDate)|\(type.rawValue)"
        }
    }

    private var entries: [Entry] {
        sessions.flatMap { session in
            [
                Entry(date: session.nightDate, type: .deep, percent: session.deepRatio * 100),
                Entry(date: session.nightDate, type: .rem, percent: session.remRatio * 100),
                Entry(date: session.nightDate, type: .core, percent: session.coreRatio * 100),
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stage Percentages")
                .font(.headline)
            Text("Stage share as a percentage of total sleep")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Chart(entries) { entry in
                LineMark(
                    x: .value("Date", entry.date, unit: .day),
                    y: .value("Percent", entry.percent)
                )
                .foregroundStyle(by: .value("Stage", entry.type.rawValue))
                .interpolationMethod(.catmullRom)
            }
            .chartForegroundStyleScale([
                SleepStageType.deep.rawValue: Color.sleepDeep,
                SleepStageType.rem.rawValue: Color.sleepREM,
                SleepStageType.core.rawValue: Color.sleepCore,
            ])
            .chartYAxisLabel("Percent")
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month().day()) } }
            .frame(height: 220)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
