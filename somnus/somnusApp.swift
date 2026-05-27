import SwiftUI

@main
struct somnusApp: App {
    @State private var store = SleepStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
