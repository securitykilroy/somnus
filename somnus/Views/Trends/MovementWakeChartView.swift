import SwiftUI
import Charts

struct MovementWakeChartView: View {
    let sessions: [SleepSession]
    var visibleDays: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Likely Out of Bed")
                .font(.headline)
            Text("Awake intervals with step or distance evidence")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(sessions) { session in
                    BarMark(
                        x: .value("Date", session.nightDate, unit: .day),
                        y: .value("Events", session.movementConfirmedAwakeningCount)
                    )
                    .foregroundStyle(Color.orange.gradient)
                    .cornerRadius(3)

                    if session.likelyOutOfBedDuration > 0 {
                        PointMark(
                            x: .value("Date", session.nightDate, unit: .day),
                            y: .value("Events", session.movementConfirmedAwakeningCount)
                        )
                        .symbolSize(max(40, session.likelyOutOfBedDuration / 10))
                        .foregroundStyle(Color.red.opacity(0.75))
                    }
                }
            }
            .chartYAxisLabel("Events")
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month().day()) } }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: TimeInterval((visibleDays ?? max(sessions.count, 1)) * 24 * 3600))
            .frame(height: 200)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
