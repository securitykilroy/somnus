import SwiftUI
import Charts

struct StageDurationView: View {
    let session: SleepSession

    private struct StageStat: Identifiable {
        var id: String { type.rawValue }
        let type: SleepStageType
        let duration: TimeInterval
    }

    private var stats: [StageStat] {
        [
            StageStat(type: .deep,  duration: session.deepDuration),
            StageStat(type: .rem,   duration: session.remDuration),
            StageStat(type: .core,  duration: session.coreDuration),
            StageStat(type: .asleepUnspecified, duration: session.unspecifiedSleepDuration),
            StageStat(type: .awake, duration: session.awakeDuration),
        ].filter { $0.duration > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time in Each Stage")
                .font(.headline)

            Chart(stats) { stat in
                BarMark(
                    x: .value("Hours", stat.duration.asHours),
                    y: .value("Stage", stat.type.rawValue)
                )
                .foregroundStyle(stat.type.color)
                .cornerRadius(4)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(stat.duration.hoursAndMinutes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    if let h = value.as(Double.self) {
                        AxisValueLabel { Text("\(h, specifier: "%.0f")h") }
                    }
                    AxisGridLine()
                }
            }
            .frame(height: 160)

            // Legend strip
            HStack(spacing: 16) {
                ForEach(stats) { stat in
                    Label(stat.type.rawValue, systemImage: "square.fill")
                        .font(.caption2)
                        .foregroundStyle(stat.type.color)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
