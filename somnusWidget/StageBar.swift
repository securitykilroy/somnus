import SwiftUI

extension SleepWidgetStage {
    /// Mirrors `Color+SleepStage` in the app so the widget and the app read as
    /// one product. Duplicated rather than shared because the app's palette is
    /// keyed by `SleepStageType`, which pulls in HealthKit.
    var color: Color {
        switch self {
        case .core:        return .blue
        case .deep:        return .indigo
        case .rem:         return .orange
        case .unspecified: return .teal.opacity(0.75)
        case .awake:       return .red.opacity(0.7)
        }
    }
}

/// Proportional strip of the night, in clock order of importance rather than
/// chronological order — the snapshot carries totals, not a timeline.
struct StageBar: View {
    let slices: [SleepWidgetStageSlice]
    var height: CGFloat = 8

    private var total: TimeInterval {
        slices.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(slices, id: \.stage) { slice in
                    slice.stage.color
                        .frame(width: width(for: slice, in: geometry.size.width))
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
        .accessibilityHidden(true)
    }

    private func width(for slice: SleepWidgetStageSlice, in available: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        return available * CGFloat(slice.duration / total)
    }
}

/// Legend for the large sizes, where the bar has room to be explained.
struct StageLegend: View {
    let slices: [SleepWidgetStageSlice]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(slices, id: \.stage) { slice in
                HStack(spacing: 4) {
                    Circle()
                        .fill(slice.stage.color)
                        .frame(width: 6, height: 6)
                    Text(slice.stage.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
