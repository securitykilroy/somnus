import SwiftUI
import Charts

struct StageBreakdownChartView: View {
    let sessions: [SleepSession]

    private struct Entry: Identifiable {
        let date: Date
        let type: SleepStageType
        let hours: Double

        var id: String {
            "\(date.timeIntervalSinceReferenceDate)|\(type.rawValue)"
        }
    }

    // Stacked in display order: deep at base, then core, rem, awake on top
    private let stageOrder: [SleepStageType] = [.deep, .core, .rem, .asleepUnspecified, .awake]

    private var entries: [Entry] {
        sessions.flatMap { session in
            stageOrder.map { type in
                let duration: TimeInterval
                switch type {
                case .deep:  duration = session.deepDuration
                case .core:  duration = session.coreDuration
                case .rem:   duration = session.remDuration
                case .awake: duration = session.awakeDuration
                case .asleepUnspecified: duration = session.unspecifiedSleepDuration
                case .inBed: duration = 0
                }
                return Entry(date: session.nightDate, type: type, hours: duration.asHours)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stage Breakdown")
                .font(.headline)

            Chart(entries) { entry in
                BarMark(
                    x: .value("Date", entry.date, unit: .day),
                    y: .value("Hours", entry.hours)
                )
                .foregroundStyle(by: .value("Stage", entry.type.rawValue))
                .cornerRadius(2)
            }
            .chartForegroundStyleScale([
                SleepStageType.deep.rawValue:  Color.sleepDeep,
                SleepStageType.core.rawValue:  Color.sleepCore,
                SleepStageType.rem.rawValue:   Color.sleepREM,
                SleepStageType.asleepUnspecified.rawValue: Color.sleepUnspecified,
                SleepStageType.awake.rawValue: Color.sleepAwake,
            ])
            .chartLegend(position: .bottom, alignment: .leading)
            .chartYAxisLabel("Hours")
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month().day()) } }
            .frame(height: 220)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
