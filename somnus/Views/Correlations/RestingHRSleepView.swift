import SwiftUI
import Charts

struct RestingHRSleepView: View {
    let sessions: [SleepSession]
    let dailyRestingHR: [DailyMetricSample]

    private var meanRHR: Double {
        guard !dailyRestingHR.isEmpty else { return 0 }
        return dailyRestingHR.reduce(0) { $0 + $1.value } / Double(dailyRestingHR.count)
    }

    private var xAxisMarks: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 6)) { _ in
            AxisGridLine()
            AxisValueLabel(format: .dateTime.month().day())
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resting Heart Rate vs Sleep Duration")
                .font(.headline)
            Text("Elevated RHR often follows nights of insufficient sleep")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if dailyRestingHR.isEmpty {
                Text("No resting heart rate data available — requires Apple Watch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                Text("Resting Heart Rate")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Chart {
                    ForEach(dailyRestingHR) { sample in
                        LineMark(
                            x: .value("Date", sample.date, unit: .day),
                            y: .value("BPM", sample.value)
                        )
                        .foregroundStyle(Color.red)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", sample.date, unit: .day),
                            y: .value("BPM", sample.value)
                        )
                        .foregroundStyle(Color.red)
                        .symbolSize(25)
                    }

                    RuleMark(y: .value("Mean", meanRHR))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .trailing) {
                            Text("avg \(Int(meanRHR)) bpm")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
                .chartYAxisLabel("bpm")
                .chartXAxis { xAxisMarks }
                .frame(height: 130)

                Text("Sleep Duration")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                Chart {
                    ForEach(sessions) { session in
                        BarMark(
                            x: .value("Date", session.nightDate, unit: .day),
                            y: .value("Hours", session.totalSleep.asHours)
                        )
                        .foregroundStyle(Color.blue.gradient)
                        .cornerRadius(3)
                    }

                    RuleMark(y: .value("8h", 8.0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.red.opacity(0.4))
                }
                .chartYAxisLabel("hours")
                .chartXAxis { xAxisMarks }
                .frame(height: 130)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
