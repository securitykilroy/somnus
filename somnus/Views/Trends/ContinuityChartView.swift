import SwiftUI
import Charts

struct ContinuityChartView: View {
    let sessions: [SleepSession]
    var visibleDays: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continuity")
                .font(.headline)
            Text("Awake time and fragmentation after sleep starts")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(sessions) { session in
                    LineMark(
                        x: .value("Date", session.nightDate, unit: .day),
                        y: .value("WASO", session.wakeAfterSleepOnset.asHours)
                    )
                    .foregroundStyle(Color.red)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", session.nightDate, unit: .day),
                        y: .value("WASO", session.wakeAfterSleepOnset.asHours)
                    )
                    .foregroundStyle(Color.red)
                }
            }
            .chartYAxisLabel("Awake hours")
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month().day()) } }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: TimeInterval((visibleDays ?? max(sessions.count, 1)) * 24 * 3600))
            .frame(height: 200)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
