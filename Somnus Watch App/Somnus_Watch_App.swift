import SwiftUI
import WidgetKit

struct SleepLatencyEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSleepLatencySnapshot?
}

struct SleepLatencyProvider: TimelineProvider {
    func placeholder(in context: Context) -> SleepLatencyEntry {
        SleepLatencyEntry(
            date: Date(),
            snapshot: WidgetSleepLatencySnapshot(
                nightDate: Date(),
                latency: 28 * 60,
                appleLatency: 0
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SleepLatencyEntry) -> Void) {
        Task {
            let snapshot = await WidgetSomnusStore().latestLatencySnapshot()
            completion(SleepLatencyEntry(date: Date(), snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepLatencyEntry>) -> Void) {
        Task {
            let snapshot = await WidgetSomnusStore().latestLatencySnapshot()
            let entry = SleepLatencyEntry(date: Date(), snapshot: snapshot)
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }
}

struct Somnus_Watch_AppEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SleepLatencyEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryInline:
            inlineView
        default:
            rectangularView
        }
    }

    private var circularView: some View {
        VStack(spacing: 2) {
            Image(systemName: "bed.double.fill")
                .font(.caption2)
            Text(latencyText)
                .font(.caption.weight(.semibold))
                .minimumScaleFactor(0.7)
        }
    }

    private var inlineView: some View {
        Label("Latency \(latencyText)", systemImage: "bed.double.fill")
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("Sleep Latency", systemImage: "bed.double.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(latencyText)
                .font(.headline.weight(.semibold))
                .minimumScaleFactor(0.7)
            if let snapshot = entry.snapshot {
                Text(snapshot.nightDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var latencyText: String {
        entry.snapshot?.latency.somnusWidgetDuration ?? "--"
    }
}

struct Somnus_Watch_App: Widget {
    let kind = "SomnusSleepLatency"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SleepLatencyProvider()) { entry in
            Somnus_Watch_AppEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Sleep Latency")
        .description("Shows the latest Somnus sleep latency.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .accessoryRectangular) {
    Somnus_Watch_App()
} timeline: {
    SleepLatencyEntry(
        date: .now,
        snapshot: WidgetSleepLatencySnapshot(
            nightDate: .now,
            latency: 32 * 60,
            appleLatency: 0
        )
    )
}
