import Charts
import SwiftUI

struct SleepLatencyTrendView: View {
    let records: [SleepLatencyRecord]
    let summary: SleepLatencySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep Latency")
                .font(.headline)
            Text("Self-reported trying-to-sleep time vs first Apple-detected sleep")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if records.isEmpty {
                ContentUnavailableView(
                    "No Intent Data",
                    systemImage: "bed.double",
                    description: Text("Tap Trying to Sleep on Overview to start tracking self-reported latency.")
                )
                .frame(minHeight: 160)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricCardView(title: "Latest", value: summary.latestLatency?.hoursAndMinutes ?? "--")
                    MetricCardView(title: "7D Mean", value: summary.sevenDayAverage?.hoursAndMinutes ?? "--")
                    MetricCardView(title: "30D Median", value: summary.medianLatency?.hoursAndMinutes ?? "--")
                    MetricCardView(
                        title: "Longest",
                        value: summary.longestRecent?.latency.hoursAndMinutes ?? "--",
                        subtitle: summary.longestRecent?.nightDate.formatted(date: .abbreviated, time: .omitted),
                        valueColor: (summary.longestRecent?.latency ?? 0) >= 60 * 60 ? .orange : .primary
                    )
                    MetricCardView(
                        title: "Long Nights",
                        value: "\(summary.longLatencyCount)",
                        subtitle: ">=35 min in last 30",
                        valueColor: summary.longLatencyCount > 0 ? .orange : .primary
                    )
                    MetricCardView(
                        title: "Watch Mismatch",
                        value: "\(summary.appleMismatchCount)",
                        subtitle: ">=20 min from button",
                        valueColor: summary.appleMismatchCount > 0 ? .blue : .primary
                    )
                }

                latencyInterpretation
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                Chart {
                    ForEach(records) { record in
                        LineMark(
                            x: .value("Date", record.nightDate, unit: .day),
                            y: .value("Self-reported", record.latency / 60),
                            series: .value("Source", "Self-reported")
                        )
                        .foregroundStyle(.indigo)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", record.nightDate, unit: .day),
                            y: .value("Self-reported", record.latency / 60)
                        )
                        .foregroundStyle(isOutlier(record) ? .orange : .indigo)

                        if record.appleLatency > 0 {
                            PointMark(
                                x: .value("Date", record.nightDate, unit: .day),
                                y: .value("Apple-derived", record.appleLatency / 60)
                            )
                            .foregroundStyle(.blue)
                            .symbol(.square)
                        }
                    }
                }
                .chartYAxisLabel("Minutes")
                .chartForegroundStyleScale([
                    "Self-reported": Color.indigo,
                    "Apple-derived": Color.blue,
                ])
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month().day()) } }
                .frame(height: 220)

                if !summary.outliers.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Long Latency Outliers")
                            .font(.subheadline.weight(.semibold))
                        ForEach(summary.outliers.prefix(6)) { outlier in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(outlier.record.nightDate, style: .date)
                                        .font(.subheadline.weight(.medium))
                                    Text("Intent \(outlier.record.intentTime.formatted(date: .omitted, time: .shortened)); sleep \(outlier.record.firstSleepTime.formatted(date: .omitted, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(outlier.record.latency.hoursAndMinutes)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                            if outlier.id != summary.outliers.prefix(6).last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var latencyInterpretation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Latency Pattern", systemImage: "timer")
                .font(.subheadline.weight(.semibold))
            if let latest = records.last {
                Text(latencyMessage(for: latest))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let averageDelta = summary.averageAppleLatencyDelta, abs(averageDelta) >= 10 * 60 {
                Text("Apple's estimate is averaging \(abs(averageDelta).hoursAndMinutes) \(averageDelta > 0 ? "shorter" : "longer") than your button-based latency.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func latencyMessage(for record: SleepLatencyRecord) -> String {
        let prefix = "Latest button-to-sleep latency was \(record.latency.hoursAndMinutes)."
        switch record.latencyBand {
        case .quick:
            return "\(prefix) That is a quick sleep-onset night."
        case .typical:
            return "\(prefix) That sits in a typical range."
        case .long:
            return "\(prefix) That is a long sleep-onset night, worth comparing with stress, activity, caffeine, or bedtime."
        case .veryLong:
            return "\(prefix) That is a very long sleep-onset night and likely matches the lived sense of lying awake."
        }
    }

    private func isOutlier(_ record: SleepLatencyRecord) -> Bool {
        summary.outliers.contains { $0.record.id == record.id }
    }
}
