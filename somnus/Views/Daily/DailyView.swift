import SwiftUI

struct DailyView: View {
    @Environment(SleepStore.self) var store
    @State private var selectedIndex: Int = 0

    private var currentSession: SleepSession? {
        guard !store.sessions.isEmpty, selectedIndex < store.sessions.count else { return nil }
        return store.sessions[selectedIndex]
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading {
                    ProgressView("Loading sleep data...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sleep Data",
                        systemImage: "moon.zzz",
                        description: Text("Sleep data from Apple Health will appear here.")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            if store.sessions.count > 1 {
                                nightNavigator
                            }
                            if let session = currentSession {
                                statsBar(session)
                                QualityCardView(session: session)
                                analysisGrid(session)
                                AwakeEventListView(session: session)
                                HypnogramView(session: session)
                                StageDurationView(session: session)
                            }
                        }
                        .padding()
                    }
                    .refreshable { await store.load() }
                }
            }
            .navigationTitle("Daily")
            .toolbar {
                if let exportURL = dailyExportURL {
                    ShareLink(item: exportURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export Daily CSV")
                }
            }
            .onChange(of: store.sessions.count) {
                selectedIndex = 0
            }
        }
    }

    private var dailyExportURL: URL? {
        guard let currentSession else { return nil }
        return try? CSVExporter.dailyFile(for: currentSession).writeTemporaryFile()
    }

    @ViewBuilder
    private var nightNavigator: some View {
        HStack {
            Button {
                withAnimation { selectedIndex = min(selectedIndex + 1, store.sessions.count - 1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.bold())
                    .frame(width: 44, height: 44)
            }
            .disabled(selectedIndex >= store.sessions.count - 1)

            Spacer()

            VStack(spacing: 2) {
                if let session = currentSession {
                    Text(session.nightDate, style: .date)
                        .font(.headline)
                }
                Text("\(selectedIndex + 1) of \(store.sessions.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation { selectedIndex = max(selectedIndex - 1, 0) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.bold())
                    .frame(width: 44, height: 44)
            }
            .disabled(selectedIndex == 0)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func statsBar(_ session: SleepSession) -> some View {
        HStack(spacing: 0) {
            statItem("Bedtime",   value: session.startTime.formatted(date: .omitted, time: .shortened))
            Divider().frame(height: 36)
            statItem("Wake",      value: session.endTime.formatted(date: .omitted, time: .shortened))
            Divider().frame(height: 36)
            statItem("Sleep",     value: session.totalSleep.hoursAndMinutes)
            Divider().frame(height: 36)
            statItem("Efficiency", value: "\(Int(session.efficiency * 100))%")
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func statItem(_ label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func analysisGrid(_ session: SleepSession) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCardView(title: "Latency", value: session.sleepLatency.hoursAndMinutes, subtitle: "time to first sleep")
            MetricCardView(title: "WASO", value: session.wakeAfterSleepOnset.hoursAndMinutes, subtitle: "awake after sleep onset")
            MetricCardView(title: "Awakenings", value: "\(session.awakeningCount)", subtitle: "within the sleep window")
            MetricCardView(title: "Out of Bed", value: "\(session.movementConfirmedAwakeningCount)", subtitle: session.likelyOutOfBedDuration.hoursAndMinutes, valueColor: session.movementConfirmedAwakeningCount > 0 ? .orange : .primary)
            MetricCardView(title: "REM Latency", value: session.remLatency?.hoursAndMinutes ?? "n/a", subtitle: "from first sleep")
            MetricCardView(title: "Deep", value: session.deepRatio.percentString, subtitle: session.deepDuration.hoursAndMinutes)
            MetricCardView(title: "REM", value: session.remRatio.percentString, subtitle: session.remDuration.hoursAndMinutes)
        }
    }
}
