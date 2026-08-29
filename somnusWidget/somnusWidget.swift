import SwiftUI
import WidgetKit

struct SleepEntry: TimelineEntry {
    let date: Date
    /// `nil` when the app has not published a night yet — first run, or Health
    /// access never granted.
    let snapshot: SleepWidgetSnapshot?
}

struct Provider: TimelineProvider {
    private let snapshots = SleepWidgetSnapshotStore()

    func placeholder(in context: Context) -> SleepEntry {
        SleepEntry(date: .now, snapshot: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (SleepEntry) -> Void) {
        // The gallery should show what a good night looks like, not the empty
        // state, so previews always get sample data.
        let snapshot = context.isPreview ? .sample() : snapshots.read()
        completion(SleepEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepEntry>) -> Void) {
        let entry = SleepEntry(date: .now, snapshot: snapshots.read())
        // The app pushes a reload the moment new sleep data lands, so this is
        // only a fallback — it exists to keep the "2d" staleness marker honest
        // on days the app never runs.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now)
            ?? Date.now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct somnusWidget: Widget {
    let kind: String = "somnusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            SleepWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Last Night")
        .description("Sleep stages, duration and efficiency from your most recent night.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .systemExtraLarge,
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline,
        ])
    }
}

#Preview("Small", as: .systemSmall) {
    somnusWidget()
} timeline: {
    SleepEntry(date: .now, snapshot: .sample())
}

#Preview("Medium", as: .systemMedium) {
    somnusWidget()
} timeline: {
    SleepEntry(date: .now, snapshot: .sample())
}

#Preview("Large", as: .systemLarge) {
    somnusWidget()
} timeline: {
    SleepEntry(date: .now, snapshot: .sample())
}

#Preview("Rectangular", as: .accessoryRectangular) {
    somnusWidget()
} timeline: {
    SleepEntry(date: .now, snapshot: .sample())
    SleepEntry(date: .now, snapshot: .sample(
        nightDate: Calendar.current.date(byAdding: .day, value: -2, to: Date())!
    ))
}

#Preview("Circular", as: .accessoryCircular) {
    somnusWidget()
} timeline: {
    SleepEntry(date: .now, snapshot: .sample())
}

#Preview("Inline", as: .accessoryInline) {
    somnusWidget()
} timeline: {
    SleepEntry(date: .now, snapshot: .sample())
}

#Preview("Empty", as: .systemSmall) {
    somnusWidget()
} timeline: {
    SleepEntry(date: .now, snapshot: nil)
}
