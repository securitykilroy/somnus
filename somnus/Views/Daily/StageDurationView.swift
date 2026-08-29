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

    /// Headroom past the longest bar so the trailing duration label has
    /// somewhere to sit. Without it the longest bar ends at the plot edge and
    /// its label is laid out into zero width.
    private var xDomainUpperBound: Double {
        let longest = stats.map(\.duration.asHours).max() ?? 1
        return max(longest * 1.3, 1)
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
                .annotation(
                    position: .trailing,
                    alignment: .center,
                    spacing: 6,
                    // Pull a label back inside rather than letting it clip.
                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                ) {
                    Text(stat.duration.hoursAndMinutes)
                        // Charts proposes zero width to an annotation with no
                        // room, which truncates the text away entirely.
                        .fixedSize()
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXScale(domain: 0...xDomainUpperBound)
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

#Preview {
    let start = Calendar.current.date(byAdding: .hour, value: -8, to: Date())!
    // Built inline rather than via a helper function: a local `func` does not
    // inherit the preview body's main-actor isolation.
    let spans: [(SleepStageType, Double, Double)] = [
        (.core, 0, 2.4),
        (.deep, 2.4, 0.8),
        (.rem, 3.2, 1.5),
        (.awake, 4.7, 0.6),
        (.core, 5.3, 2.2),
    ]

    StageDurationView(
        session: SleepSession(
            nightDate: Calendar.current.startOfDay(for: Date()),
            stages: spans.map { type, offsetHours, lengthHours in
                SleepStage(
                    startDate: start.addingTimeInterval(offsetHours * 3600),
                    endDate: start.addingTimeInterval((offsetHours + lengthHours) * 3600),
                    type: type
                )
            }
        )
    )
    .padding()
}
