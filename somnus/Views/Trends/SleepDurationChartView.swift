import SwiftUI
import Charts

struct SleepDurationChartView: View {
    let sessions: [SleepSession]

    private var mean: TimeInterval {
        guard !sessions.isEmpty else { return 0 }
        return sessions.reduce(0.0) { $0 + $1.totalSleep } / Double(sessions.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sleep Duration")
                .font(.headline)
            Text("Mean: \(mean.hoursAndMinutes)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(sessions) { session in
                    BarMark(
                        x: .value("Date", session.nightDate, unit: .day),
                        y: .value("Hours", session.totalSleep.asHours)
                    )
                    .foregroundStyle(Color.blue.gradient)
                    .cornerRadius(3)
                }

                RuleMark(y: .value("Mean", mean.asHours))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg \(mean.hoursAndMinutes)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                RuleMark(y: .value("8h target", 8.0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(.red.opacity(0.5))
                    .annotation(position: .bottom, alignment: .trailing) {
                        Text("8h")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.7))
                    }
            }
            .chartYAxisLabel("Hours")
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: xAxisCount)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month().day()) } }
            .frame(height: 200)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var xAxisCount: Int {
        switch sessions.count {
        case ...14: return sessions.count
        case ...60: return 8
        default:    return 6
        }
    }
}
