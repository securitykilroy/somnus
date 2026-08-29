import Foundation

/// Shared so an intent can refresh the widget without importing the widget
/// target, which it cannot see.
enum MealWidgetKind {
    static let value = "MealLogWidget"
}

enum MealLogIntentError: Error, CustomLocalizedStringResourceConvertible {
    case storeUnavailable
    case nothingToUndo

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .storeUnavailable:
            return "Somnus could not reach its shared storage, so the meal was not saved."
        case .nothingToUndo:
            return "There is no recent meal entry to undo."
        }
    }
}
