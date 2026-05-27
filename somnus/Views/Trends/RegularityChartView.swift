import SwiftUI
import Charts

struct RegularityChartView: View {
    let sessions: [SleepSession]
    var visibleDays: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Regularity")
                .font(.headline)
            Text("Bedtime and wake-time drift")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(sessions) { session in
                    PointMark(
                        x: .value("Date", session.nightDate, unit: .day),
                        y: .value("Bedtime", hourValue(session.startTime))
                    )
                    .foregroundStyle(by: .value("Time", "Bedtime"))

                    PointMark(
                        x: .value("Date", session.nightDate, unit: .day),
                        y: .value("Wake", hourValue(session.endTime))
                    )
                    .foregroundStyle(by: .value("Time", "Wake"))
                }
            }
            .chartForegroundStyleScale([
                "Bedtime": Color.indigo,
                "Wake": Color.orange,
            ])
            .chartYAxis {
                AxisMarks(values: .stride(by: 3)) { value in
                    if let hour = value.as(Double.self) {
                        AxisValueLabel(formatHour(hour))
                    }
                    AxisGridLine()
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month().day()) } }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: TimeInterval((visibleDays ?? max(sessions.count, 1)) * 24 * 3600))
            .frame(height: 220)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func hourValue(_ date: Date) -> Double {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
        return hour < 12 ? hour + 24 : hour
    }

    private func formatHour(_ value: Double) -> String {
        let hour = Int(value.rounded()) % 24
        return "\(hour):00"
    }
}
