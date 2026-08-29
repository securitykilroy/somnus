import SwiftUI
import Charts

struct MetricScatterChartView: View {
    let title: String
    let points: [(x: Double, y: Double)]
    let color: Color
    let xAxisLabel: String
    let yAxisLabel: String
    let interpretation: (Double) -> String

    private var regression: (slope: Double, intercept: Double)? {
        CorrelationStatistics.linearRegression(points.map(\.x), points.map(\.y))
    }

    private var r: Double? {
        CorrelationStatistics.pearsonR(points.map(\.x), points.map(\.y))
    }

    private var classification: (strength: CorrelationStrength, label: String, color: Color)? {
        r.map(CorrelationStrength.classify)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                if let classification, points.count >= 3 {
                    Text(classification.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(classification.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(classification.color.opacity(0.15), in: Capsule())
                }
            }

            if points.count < 3 {
                Text("Not enough paired data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            } else {
                let xMin = points.map(\.x).min()!
                let xMax = points.map(\.x).max()!

                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, pt in
                        PointMark(
                            x: .value(xAxisLabel, pt.x),
                            y: .value(yAxisLabel, pt.y)
                        )
                        .foregroundStyle(color.opacity(0.7))
                        .symbolSize(30)
                    }

                    if let reg = regression {
                        let linePoints = [
                            (x: xMin, y: reg.slope * xMin + reg.intercept),
                            (x: xMax, y: reg.slope * xMax + reg.intercept),
                        ]
                        ForEach(Array(linePoints.enumerated()), id: \.offset) { _, pt in
                            LineMark(
                                x: .value(xAxisLabel, pt.x),
                                y: .value(yAxisLabel, pt.y)
                            )
                            .foregroundStyle(color.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5]))
                        }
                    }
                }
                .chartXAxisLabel(xAxisLabel)
                .chartYAxisLabel(yAxisLabel)
                .frame(height: 150)

                if let r, let reg = regression {
                    Text("r = \(String(format: "%.2f", r))" + (abs(r) >= 0.1 ? " · \(interpretation(reg.slope))" : ""))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
