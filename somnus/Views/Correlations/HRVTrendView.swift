import SwiftUI
import Charts

struct HRVTrendView: View {
    let dailyHRV: [DailyMetricSample]
    let sessions: [SleepSession]

    private var rollingMean: [DailyMetricSample] {
        guard dailyHRV.count >= 3 else { return dailyHRV }
        let sorted = dailyHRV.sorted { $0.date < $1.date }
        return sorted.enumerated().map { i, sample in
            let window = sorted[max(0, i - 6)...i]
            let avg = window.reduce(0.0) { $0 + $1.value } / Double(window.count)
            return DailyMetricSample(date: sample.date, value: avg)
        }
    }

    private var mean: Double {
        guard !dailyHRV.isEmpty else { return 0 }
        return dailyHRV.reduce(0) { $0 + $1.value } / Double(dailyHRV.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heart Rate Variability")
                .font(.headline)
            Text("Higher HRV generally indicates better recovery and sleep quality")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if dailyHRV.isEmpty {
                Text("No HRV data available — requires Apple Watch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                Chart {
                    ForEach(dailyHRV) { sample in
                        PointMark(
                            x: .value("Date", sample.date, unit: .day),
                            y: .value("HRV (ms)", sample.value)
                        )
                        .foregroundStyle(Color.purple.opacity(0.5))
                        .symbolSize(25)
                    }

                    ForEach(rollingMean) { sample in
                        LineMark(
                            x: .value("Date", sample.date, unit: .day),
                            y: .value("7d avg", sample.value)
                        )
                        .foregroundStyle(Color.purple)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }

                    RuleMark(y: .value("Mean", mean))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .trailing) {
                            Text("avg \(Int(mean))ms")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
                .chartYAxisLabel("ms")
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: TimeInterval(max(dailyHRV.count, 1) * 24 * 3600))
                .frame(height: 200)

                HStack(spacing: 12) {
                    legendDot(.purple.opacity(0.5), "Daily HRV")
                    legendDot(.purple, "7-day avg")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}
