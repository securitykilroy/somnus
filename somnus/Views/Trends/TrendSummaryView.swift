import SwiftUI

struct TrendSummaryView: View {
    let summary: SleepTrendSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Baseline")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricCardView(title: "7D Mean", value: summary.sevenDayMean.hoursAndMinutes)
                MetricCardView(title: "30D Mean", value: summary.thirtyDayMean.hoursAndMinutes)
                MetricCardView(title: "Acute Debt", value: summary.acuteDebt.hoursAndMinutes, subtitle: "last 7 days", valueColor: .red)
                MetricCardView(title: "Chronic Debt", value: summary.chronicDebt.hoursAndMinutes, subtitle: "last 30 days", valueColor: .red)
                MetricCardView(title: "Out of Bed", value: "\(summary.totalMovementConfirmedWakeups)", subtitle: summary.totalLikelyOutOfBedDuration.hoursAndMinutes, valueColor: summary.totalMovementConfirmedWakeups > 0 ? .orange : .primary)
                MetricCardView(title: "Bedtime Drift", value: summary.bedtimeVariability.hoursAndMinutes)
                MetricCardView(title: "Social Jetlag", value: summary.socialJetlag.hoursAndMinutes)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct OutlierListView: View {
    let outliers: [SleepOutlier]

    var body: some View {
        if !outliers.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Outliers")
                    .font(.headline)
                ForEach(outliers.prefix(8)) { outlier in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(outlier.session.nightDate, style: .date)
                                .font(.subheadline.bold())
                            Text("\(outlier.metric): \(outlier.value.hoursAndMinutes), \(abs(outlier.deviation).hoursAndMinutes) \(outlier.deviation > 0 ? "above" : "below") baseline")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: outlier.deviation > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .foregroundStyle(outlier.deviation > 0 ? .green : .red)
                    }
                    if outlier.id != outliers.prefix(8).last?.id {
                        Divider()
                    }
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
