import AppIntents
import SwiftUI
import WidgetKit

struct MealEntry: TimelineEntry {
    let date: Date
    /// Today's entries, newest first.
    let todaysMeals: [MealEvent]
    /// The newest entry regardless of day, so the widget can still say "14h ago"
    /// first thing in the morning.
    let lastMeal: MealEvent?

    var canUndo: Bool {
        guard let lastMeal else { return false }
        return date.timeIntervalSince(lastMeal.createdAt) <= 15 * 60
    }
}

struct MealProvider: TimelineProvider {
    private let meals = MealLogStore()

    func placeholder(in context: Context) -> MealEntry {
        MealEntry.sample()
    }

    func getSnapshot(in context: Context, completion: @escaping (MealEntry) -> Void) {
        // The gallery should show the widget doing its job, not an empty log.
        completion(context.isPreview ? .sample() : entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MealEntry>) -> Void) {
        // Every intent reloads this widget the moment it writes, so the schedule
        // is only a fallback. It exists to roll the "today" list over at
        // midnight when nothing has been logged for a while.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now)
            ?? Date.now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry()], policy: .after(next)))
    }

    private func entry(now: Date = .now) -> MealEntry {
        let all = meals.read()
        return MealEntry(
            date: now,
            todaysMeals: all.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: now) },
            lastMeal: all.first
        )
    }
}

struct MealLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MealWidgetKind.value, provider: MealProvider()) { entry in
            MealLogWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Meal Log")
        .description("Log that you ate without opening Somnus, and see how long it has been.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MealLogWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MealEntry

    var body: some View {
        switch family {
        case .systemMedium: mediumBody
        default: smallBody
        }
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            sinceLastMeal
            Spacer(minLength: 0)
            logButton(minutesAgo: 0, label: "Ate now", systemImage: "fork.knife")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mediumBody: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                sinceLastMeal
                Spacer(minLength: 0)
                logButton(minutesAgo: 0, label: "Ate now", systemImage: "fork.knife")
                HStack(spacing: 6) {
                    logButton(minutesAgo: 30, label: "30m ago", systemImage: nil)
                    logButton(minutesAgo: 60, label: "1h ago", systemImage: nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Today")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if entry.canUndo {
                        Button(intent: UndoLastMealIntent()) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Undo last meal entry")
                    }
                }

                if entry.todaysMeals.isEmpty {
                    Text("Nothing logged yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(entry.todaysMeals.prefix(4)) { meal in
                        HStack(spacing: 6) {
                            Text(meal.timestamp, format: .dateTime.hour().minute())
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(meal.displayLabel)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Relative style rather than a computed interval so the label keeps
    /// counting up between timeline reloads.
    @ViewBuilder
    private var sinceLastMeal: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Last meal")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let lastMeal = entry.lastMeal {
                Text(lastMeal.timestamp, style: .relative)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(lastMeal.displayLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("None logged")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func logButton(minutesAgo: Int, label: String, systemImage: String?) -> some View {
        Button(intent: QuickLogMealIntent(minutesAgo: minutesAgo)) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

extension MealEntry {
    static func sample(now: Date = .now) -> MealEntry {
        let meals = [
            MealEvent(timestamp: now.addingTimeInterval(-2 * 3600), note: "Pasta and salad"),
            MealEvent(timestamp: now.addingTimeInterval(-7 * 3600), note: "Turkey sandwich"),
            MealEvent(timestamp: now.addingTimeInterval(-11 * 3600), note: "Oatmeal"),
        ]
        return MealEntry(date: now, todaysMeals: meals, lastMeal: meals.first)
    }
}

#Preview("Small", as: .systemSmall) {
    MealLogWidget()
} timeline: {
    MealEntry.sample()
}

#Preview("Medium", as: .systemMedium) {
    MealLogWidget()
} timeline: {
    MealEntry.sample()
}

#Preview("Empty", as: .systemMedium) {
    MealLogWidget()
} timeline: {
    MealEntry(date: .now, todaysMeals: [], lastMeal: nil)
}
