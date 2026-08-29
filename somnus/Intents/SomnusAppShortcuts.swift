import AppIntents

/// Lives in the app target because App Shortcuts are published by the app, not
/// by an extension.
///
/// The description is not a spoken parameter: App Shortcut phrases can only
/// interpolate `AppEnum` and `AppEntity` values, so a free-text note cannot ride
/// in the phrase itself. Siri asks for it instead, via the parameter's
/// `requestValueDialog`.
struct SomnusAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogMealIntent(),
            phrases: [
                "Log a meal in \(.applicationName)",
                "Log what I ate in \(.applicationName)",
                "Record a meal in \(.applicationName)",
                "Log food in \(.applicationName)",
            ],
            shortTitle: "Log Meal",
            systemImageName: "fork.knife"
        )
    }
}
