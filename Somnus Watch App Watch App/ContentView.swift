import SwiftUI

struct ContentView: View {
    @Environment(WatchSomnusStore.self) private var store
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        logTryingToSleep()
                    } label: {
                        Label("Trying to Sleep", systemImage: "bed.double.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isLoading)

                    if let statusMessage {
                        Label(statusMessage, systemImage: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(statusIsError ? .orange : .green)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last Logged")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let latestIntent = store.latestIntent {
                            Text(latestIntent.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.headline)
                        } else {
                            Text("No sleep intent yet")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Latest Latency")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let snapshot = store.latestLatencySnapshot {
                            Text(snapshot.latency.somnusShortDuration)
                                .font(.title2.weight(.semibold))
                            Text(snapshot.nightDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No matched night yet")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            .navigationTitle("Somnus")
            .task {
                store.load()
            }
        }
    }

    private func logTryingToSleep() {
        do {
            try store.addTryingToSleep()
            statusMessage = "Logged now"
            statusIsError = false
        } catch {
            statusMessage = "Could not log"
            statusIsError = true
        }
    }
}

#Preview {
    ContentView()
        .environment(WatchSomnusStore())
}
