import SwiftUI

struct ContentView: View {
    @Environment(SleepStore.self) var store

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
        .task { await store.load() }
    }
}

#Preview {
    ContentView()
        .environment(SleepStore())
}
