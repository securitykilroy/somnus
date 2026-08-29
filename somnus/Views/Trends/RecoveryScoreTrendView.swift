import SwiftUI
import Charts

struct RecoveryScoreTrendView: View {
    let scores: [RecoveryScore]

    private var mean: Double {
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0) { $0 + $1.score } / Double(scores.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recovery Score")
                .font(.headline)
            Text("HRV, resting heart rate, deep sleep, and continuity vs your own baseline over this range")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if scores.count < 3 {
                Text("Not enough data to compute a recovery score")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                Chart {
                    ForEach(scores) { entry in
                        LineMark(
                            x: .value("Date", entry.date, unit: .day),
                            y: .value("Score", entry.score)
                        )
                        .foregroundStyle(Color.green)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", entry.date, unit: .day),
                            y: .value("Score", entry.score)
                        )
                        .foregroundStyle(Color.green)
                        .symbolSize(20)
                    }

                    RuleMark(y: .value("Baseline", 50))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .trailing) {
                            Text("baseline 50")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
                .chartYScale(domain: 0...100)
                .chartYAxisLabel("score")
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .frame(height: 200)

                Text("Average over range: \(Int(mean.rounded()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
