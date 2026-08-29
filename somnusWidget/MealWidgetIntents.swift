import AppIntents
import Foundation
import WidgetKit

/// The widget-button entry point: no prompts and no parameters to resolve, so
/// the tap is handled inside the widget process and the app never launches.
///
/// `minutesAgo` exists because eating and remembering to log rarely coincide —
/// the medium widget offers a couple of backdated options so a late tap still
/// records roughly the right time.
struct QuickLogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick-Log a Meal"
    static let description = IntentDescription(
        "Records that you ate, without asking what.",
        categoryName: "Meals"
    )
    static let openAppWhenRun = false
    // Hidden from Shortcuts: the app publishes `LogMealIntent` for that, and a
    // second nearly-identical action would only be confusing.
    static let isDiscoverable = false

    @Parameter(title: "Minutes Ago", default: 0)
    var minutesAgo: Int

    init() {}

    init(minutesAgo: Int) {
        self.minutesAgo = minutesAgo
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let timestamp = Date().addingTimeInterval(-Double(minutesAgo) * 60)
        guard MealLogStore().append(at: timestamp) != nil else {
            throw MealLogIntentError.storeUnavailable
        }

        WidgetCenter.shared.reloadTimelines(ofKind: MealWidgetKind.value)
        return .result()
    }
}

/// The escape hatch for a mis-tapped widget button, deliberately limited to
/// entries a few minutes old so it can never quietly eat real history.
struct UndoLastMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Undo Last Meal Entry"
    static let description = IntentDescription(
        "Removes the meal entry you just recorded.",
        categoryName: "Meals"
    )
    static let openAppWhenRun = false
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        guard MealLogStore().removeMostRecent() != nil else {
            throw MealLogIntentError.nothingToUndo
        }

        WidgetCenter.shared.reloadTimelines(ofKind: MealWidgetKind.value)
        return .result()
    }
}
