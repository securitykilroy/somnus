import SwiftUI
import WidgetKit

struct SleepWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SleepEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .accessoryInline:      InlineView(snapshot: snapshot, now: entry.date)
            case .accessoryCircular:    CircularView(snapshot: snapshot, now: entry.date)
            case .accessoryRectangular: RectangularView(snapshot: snapshot, now: entry.date)
            case .systemSmall:          SmallView(snapshot: snapshot, now: entry.date)
            case .systemMedium:         MediumView(snapshot: snapshot, now: entry.date)
            default:                    LargeView(snapshot: snapshot, now: entry.date)
            }
        } else {
            EmptyStateView(family: family)
        }
    }
}

// MARK: - Lock screen

private struct InlineView: View {
    let snapshot: SleepWidgetSnapshot
    let now: Date

    var body: some View {
        // No room for a date here, so a stale reading leads with its own date
        // instead of the efficiency it would otherwise show.
        if let badge = snapshot.stalenessBadge(now: now) {
            Text("\(badge) ago · \(snapshot.totalSleep.hoursAndMinutes)")
        } else {
            Text("\(snapshot.totalSleep.hoursAndMinutes) · \(snapshot.efficiency.percentString)")
        }
    }
}

private struct CircularView: View {
    let snapshot: SleepWidgetSnapshot
    let now: Date

    var body: some View {
        Gauge(value: min(max(snapshot.efficiency, 0), 1)) {
            Text("Sleep")
        } currentValueLabel: {
            // The staleness marker takes the centre when the night is not
            // last night — a stale gauge must never read as a fresh one.
            Text(snapshot.stalenessBadge(now: now) ?? snapshot.totalSleep.compactDuration)
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
        .accessibilityLabel("Sleep efficiency \(snapshot.efficiency.percentString)")
    }
}

private struct RectangularView: View {
    let snapshot: SleepWidgetSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(snapshot.totalSleep.hoursAndMinutes)
                    .fontWeight(.semibold)
                Text("·")
                Text(snapshot.efficiency.percentString)
                if let badge = snapshot.stalenessBadge(now: now) {
                    Spacer(minLength: 2)
                    Text(badge)
                        .foregroundStyle(.secondary)
                }
            }
            .widgetAccentable()

            stageLine(snapshot.rem, name: "REM")
            stageLine(snapshot.deep, name: "Deep")
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func stageLine(_ slice: SleepWidgetStageSlice?, name: String) -> some View {
        if let slice {
            Text("\(name) \(slice.duration.hoursAndMinutes) (\(slice.ratio.percentString))")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Home screen

private struct SmallView: View {
    let snapshot: SleepWidgetSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DateHeader(snapshot: snapshot, now: now)

            Text(snapshot.totalSleep.hoursAndMinutes)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text("\(snapshot.efficiency.percentString) efficiency")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer(minLength: 2)

            StageBar(slices: snapshot.slices, height: 6)

            HStack(spacing: 8) {
                CompactStage(slice: snapshot.rem, name: "REM")
                CompactStage(slice: snapshot.deep, name: "Deep")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MediumView: View {
    let snapshot: SleepWidgetSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                DateHeader(snapshot: snapshot, now: now)
                Spacer()
                Text("\(snapshot.efficiency.percentString) efficiency")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(snapshot.totalSleep.hoursAndMinutes)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .lineLimit(1)

            StageBar(slices: snapshot.slices, height: 8)

            HStack(alignment: .top, spacing: 14) {
                CompactStage(slice: snapshot.rem, name: "REM", showsDuration: true)
                CompactStage(slice: snapshot.deep, name: "Deep", showsDuration: true)
                LabeledValue(name: "Latency", value: snapshot.sleepLatency.hoursAndMinutes)
                LabeledValue(name: "In bed", value: snapshot.timeInBed.hoursAndMinutes)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Also used for `.systemExtraLarge`, which is the same layout given more room —
/// the iPad Today View size.
private struct LargeView: View {
    let snapshot: SleepWidgetSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DateHeader(snapshot: snapshot, now: now)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(snapshot.totalSleep.hoursAndMinutes)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                Text("asleep")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(snapshot.efficiency.percentString)
                    .font(.system(.title2, design: .rounded, weight: .medium))
                Text("eff.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            StageBar(slices: snapshot.slices, height: 12)
            StageLegend(slices: snapshot.slices)

            VStack(spacing: 4) {
                ForEach(snapshot.slices, id: \.stage) { slice in
                    HStack {
                        Text(slice.stage.label)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(slice.duration.hoursAndMinutes)
                            .monospacedDigit()
                        // Awake time is not part of total sleep, so a percentage
                        // of it would be misleading.
                        Text(slice.stage == .awake ? "" : slice.ratio.percentString)
                            .frame(width: 42, alignment: .trailing)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.callout)
                }
            }

            Divider()

            HStack(spacing: 20) {
                LabeledValue(name: "Time in bed", value: snapshot.timeInBed.hoursAndMinutes)
                LabeledValue(name: "Latency", value: snapshot.sleepLatency.hoursAndMinutes)
                Spacer()
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shared pieces

private struct DateHeader: View {
    let snapshot: SleepWidgetSnapshot
    let now: Date

    var body: some View {
        Text(snapshot.dateLabel(now: now).uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private struct CompactStage: View {
    let slice: SleepWidgetStageSlice?
    let name: String
    var showsDuration = false

    var body: some View {
        if let slice {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if showsDuration {
                    Text(slice.duration.hoursAndMinutes)
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                }
                Text(slice.ratio.percentString)
                    .font(showsDuration ? .caption2 : .footnote.weight(.medium))
                    .foregroundStyle(showsDuration ? .secondary : .primary)
                    .monospacedDigit()
            }
        }
    }
}

private struct LabeledValue: View {
    let name: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.medium))
                .monospacedDigit()
        }
    }
}

/// Shown before the app has ever published a night. Deliberately not zeros —
/// a broken pipeline should never be mistaken for a bad night's sleep.
private struct EmptyStateView: View {
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("No sleep data")
        case .accessoryCircular:
            Image(systemName: "moon.zzz")
        default:
            VStack(spacing: 4) {
                Image(systemName: "moon.zzz")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Open Somnus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
