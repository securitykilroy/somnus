import AppIntents
import Foundation
import WidgetKit

/// The Siri and Shortcuts entry point.
///
/// Deliberately in the app target only, not in `SomnusShared`: source shared
/// with the widget extension would compile the intent into both binaries and
/// list it twice in Shortcuts. The widget's own buttons use the private intents
/// that live alongside it instead.
///
/// `openAppWhenRun` is false and the intent touches nothing but the App Group
/// file, so logging never pays for the HealthKit load the app performs when a
/// scene appears — which is the whole reason this exists outside the app's UI.
struct LogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Meal"
    static let description = IntentDescription(
        "Records roughly what you ate and when, so Somnus can line meal timing up against your sleep.",
        categoryName: "Meals",
        searchKeywords: ["meal", "eat", "food", "dinner", "snack"]
    )
    static let openAppWhenRun = false
    static let isDiscoverable = true

    @Parameter(
        title: "What You Ate",
        description: "A rough description — \"big pasta dinner\", \"two beers\".",
        requestValueDialog: "What did you eat?"
    )
    var note: String

    @Parameter(
        title: "Time",
        description: "When you ate. Defaults to now."
    )
    var when: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$note)") {
            \.$when
        }
    }

    init() {}

    init(note: String, when: Date? = nil) {
        self.note = note
        self.when = when
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let timestamp = when ?? Date()
        guard let event = MealLogStore().append(note: note, at: timestamp) else {
            throw MealLogIntentError.storeUnavailable
        }

        WidgetCenter.shared.reloadTimelines(ofKind: MealWidgetKind.value)

        let time = event.timestamp.formatted(date: .omitted, time: .shortened)
        return .result(dialog: "Logged \(event.displayLabel) at \(time).")
    }
}
