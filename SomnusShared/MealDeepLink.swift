import Foundation

/// The widget's route into the app for entries that need typing.
///
/// A widget button runs its intent headlessly and cannot present a text field,
/// so anything that needs a description has to open the app. This is the only
/// meal path that launches it.
enum MealDeepLink {
    static let scheme = "somnus"
    private static let logMealHost = "log-meal"

    static let logMeal = URL(string: "\(scheme)://\(logMealHost)")!

    static func isLogMeal(_ url: URL) -> Bool {
        url.scheme == scheme && url.host == logMealHost
    }
}
