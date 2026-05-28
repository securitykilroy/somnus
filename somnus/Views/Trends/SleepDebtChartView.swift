import SwiftUI
import Charts

struct SleepDebtChartView: View {
    let sessions: [SleepSession]

    enum DebtTarget: String, CaseIterable, Identifiable {
        case eightHours = "8 hrs"
        case sevenHours = "7 hrs"
        var id: String { rawValue }
        var seconds: TimeInterval { self == .eightHours ? 8 * 3600 : 7 * 3600 }
    }

    @State private var target: DebtTarget = .eightHours

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sleep Debt")
                    .font(.headline)
                Spacer()
                Picker("Target", selection: $target) {
                    ForEach(DebtTarget.allCases) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            let totalDebt = sessions.reduce(0.0) { $0 + max(0, target.seconds - $1.totalSleep) }
            Text("Total deficit: \(totalDebt.hoursAndMinutes)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(sessions) { session in
                    let debt = (target.seconds - session.totalSleep) / 3600
                    BarMark(
                        x: .value("Date", session.nightDate, unit: .day),
                        y: .value("Debt (h)", debt)
                    )
                    .foregroundStyle((debt > 0 ? Color.red : Color.green).gradient)
                    .cornerRadius(3)
                }

                RuleMark(y: .value("Zero", 0))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.secondary)
            }
            .chartYAxisLabel("Hours")
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month().day()) } }
            .frame(height: 200)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
