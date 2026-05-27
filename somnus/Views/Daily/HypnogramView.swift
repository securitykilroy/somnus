import SwiftUI
import Charts

struct HypnogramView: View {
    let session: SleepSession

    // Standard hypnogram order: Deep at bottom, Awake at top
    private let yDomain = ["Awake", "REM", "Core", "Unspecified Sleep", "Deep"]

    private var hypnogramStages: [SleepTimelineSegment] {
        session.normalizedTimeline.segments.filter { $0.type != .inBed }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sleep Stages")
                .font(.headline)

            if hypnogramStages.isEmpty {
                Text("Detailed stage data not available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
            } else {
                Chart(hypnogramStages) { stage in
                    RectangleMark(
                        xStart: .value("Start", stage.startDate),
                        xEnd: .value("End", stage.endDate),
                        y: .value("Stage", stage.type.rawValue)
                    )
                    .foregroundStyle(stage.type.color)
                    .cornerRadius(2)
                }
                .chartYScale(domain: yDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: .dateTime.hour().minute())
                                    .font(.caption2)
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel()
                        AxisGridLine()
                    }
                }
                .frame(height: 180)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
