import SwiftUI

struct ContentView: View {
    @Environment(SleepStore.self) var store
    @Environment(SleepIntentStore.self) var intentStore
    @Environment(PeakAlphaStore.self) var peakAlphaStore
    @Environment(MealStore.self) var mealStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var loggingMeal = false

    var body: some View {
        TabView {
            Tab("Overview", systemImage: "moon.fill") {
                OverviewView()
            }
            Tab("Daily", systemImage: "calendar") {
                DailyView()
            }
            Tab("Trends", systemImage: "chart.line.uptrend.xyaxis") {
                TrendsView()
            }
        }
        .task {
            try? await intentStore.loadAsync()
            try? await peakAlphaStore.loadAsync()
            await store.load()
        }
        .onChange(of: scenePhase) { _, phase in
            // `.task` only fires on first appearance, so without this a warm
            // resume shows whatever was loaded at the last cold launch — which
            // for an overnight-open app is the previous night.
            guard phase == .active else { return }
            // Meals can arrive from the widget or Siri while the app is
            // backgrounded, so the log is re-read on every activation — it is a
            // small local file, unlike the HealthKit refresh below.
            mealStore.reload()
            Task { await store.refreshIfStale() }
        }
        .onOpenURL { url in
            // Presented over whatever is on screen rather than routed to a tab:
            // the point of the deep link is to get a description typed and be
            // gone, not to navigate anywhere.
            guard MealDeepLink.isLogMeal(url) else { return }
            loggingMeal = true
        }
        .sheet(isPresented: $loggingMeal) {
            MealEntrySheet()
        }
        .onChange(of: store.lastLoadedAt) {
            // Covers every reload path, including ones the observer triggered
            // while the app sat in the background.
            publishLatencySnapshots()
        }
    }

    private func publishLatencySnapshots() {
        let records = SleepLatencyAnalyzer.records(
            sessions: store.sessions,
            events: intentStore.events
        )
        try? intentStore.saveLatencySnapshots(from: records)
    }
}

#Preview {
    ContentView()
        .environment(SleepStore())
        .environment(SleepIntentStore())
        .environment(PeakAlphaStore())
        .environment(MealStore())
}
