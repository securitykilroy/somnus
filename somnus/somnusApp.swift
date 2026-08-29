import SwiftUI
import UIKit

@main
struct somnusApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var store = SleepStore.shared
    @State private var intentStore = SleepIntentStore()
    @State private var peakAlphaStore = PeakAlphaStore()
    @State private var mealStore = MealStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(intentStore)
                .environment(peakAlphaStore)
                .environment(mealStore)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Observation starts here rather than in a view's `.task`. When
        // HealthKit wakes the app for newly synced sleep samples there is no
        // visible scene, so `.task` never runs — registering there would mean
        // background deliveries never re-arm and the widget would only ever be
        // as fresh as the last time the app was opened.
        Task { @MainActor in
            SleepStore.shared.startObservingSleepChanges()
        }
        return true
    }
}
