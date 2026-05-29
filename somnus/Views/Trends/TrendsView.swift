import SwiftUI

enum TrendRange: String, CaseIterable, Identifiable {
    case week        = "7D"
    case oneMonth    = "1M"
    case threeMonths = "3M"
    case sixMonths   = "6M"
    case year        = "1Y"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .week:        return 7
        case .oneMonth:    return 30
        case .threeMonths: return 90
        case .sixMonths:   return 180
        case .year:        return 365
        }
    }
}

enum TrendZoom: String, CaseIterable, Identifiable {
    case all = "All"
    case month = "30D"
    case twoWeeks = "14D"
    case week = "7D"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .all: return nil
        case .month: return 30
        case .twoWeeks: return 14
        case .week: return 7
        }
    }
}

enum TrendWindow {
    static func rangeStart(
        for range: TrendRange,
        endingAt end: Date,
        calendar: Calendar = .current
    ) -> Date {
        calendar.date(byAdding: .day, value: -range.days, to: end) ?? end
    }

    static func sessions(
        _ sessions: [SleepSession],
        range: TrendRange,
        endingAt end: Date,
        calendar: Calendar = .current
    ) -> [SleepSession] {
        let start = rangeStart(for: range, endingAt: end, calendar: calendar)
        return sessions
            .filter { $0.nightDate >= start && $0.nightDate <= end }
            .sorted { $0.nightDate < $1.nightDate }
    }

    static func visibleSessions(
        _ sessions: [SleepSession],
        zoom: TrendZoom,
        endingAt end: Date,
        calendar: Calendar = .current
    ) -> [SleepSession] {
        guard let days = zoom.days,
              let start = calendar.date(byAdding: .day, value: -days, to: end) else {
            return sessions
        }
        return sessions.filter { $0.nightDate >= start && $0.nightDate <= end }
    }

    static func metrics(
        _ samples: [DailyMetricSample],
        range: TrendRange,
        zoom: TrendZoom,
        endingAt end: Date,
        calendar: Calendar = .current
    ) -> [DailyMetricSample] {
        let rangeStart = rangeStart(for: range, endingAt: end, calendar: calendar)
        let visibleStart = zoom.days.flatMap {
            calendar.date(byAdding: .day, value: -$0, to: end)
        }
        let start = visibleStart.map { max(rangeStart, $0) } ?? rangeStart
        return samples.filter { $0.date >= start && $0.date <= end }
    }
}

struct TrendsView: View {
    @Environment(SleepStore.self) var store
    @State private var range: TrendRange = .week
    @State private var zoom: TrendZoom = .all
    @State private var rangeEnd = Date()

    private var sessions: [SleepSession] {
        TrendWindow.sessions(store.sessions, range: range, endingAt: rangeEnd)
    }

    private var visibleSessions: [SleepSession] {
        TrendWindow.visibleSessions(sessions, zoom: effectiveZoom, endingAt: rangeEnd)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    Picker("Range", selection: $range) {
                        ForEach(TrendRange.allCases) { r in Text(r.rawValue).tag(r) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if range.days > 30 {
                        Picker("Zoom", selection: $zoom) {
                            ForEach(TrendZoom.allCases) { z in Text(z.rawValue).tag(z) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }

                    if store.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if visibleSessions.isEmpty {
                        ContentUnavailableView(
                            "No Data",
                            systemImage: "chart.xyaxis.line",
                            description: Text("No sleep data in the selected time range.")
                        )
                    } else {
                        let summary = SleepTrendSummary(sessions: visibleSessions, targetSleep: 8 * 3600)

                        TrendSummaryView(summary: summary)
                            .padding(.horizontal)
                        SleepDurationChartView(sessions: visibleSessions)
                            .padding(.horizontal)
                        SleepDebtChartView(sessions: visibleSessions)
                            .padding(.horizontal)
                        ContinuityChartView(sessions: visibleSessions)
                            .padding(.horizontal)
                        MovementWakeChartView(sessions: visibleSessions)
                            .padding(.horizontal)
                        RegularityChartView(sessions: visibleSessions)
                            .padding(.horizontal)
                        StageBreakdownChartView(sessions: visibleSessions)
                            .padding(.horizontal)
                        StagePercentageChartView(sessions: visibleSessions)
                            .padding(.horizontal)
                        OutlierListView(outliers: summary.outliers)
                            .padding(.horizontal)

                        correlationsSection
                    }
                }
                .padding(.vertical)
            }
            .refreshable {
                rangeEnd = Date()
                await store.load()
            }
            .navigationTitle("Trends")
            .toolbar {
                if let exportURL = trendsExportURL {
                    ShareLink(item: exportURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export Trends CSV")
                }
            }
        }
    }

    private var effectiveZoom: TrendZoom {
        range.days <= 30 ? .all : zoom
    }

    @ViewBuilder
    private var correlationsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Correlations")
                .font(.title3.weight(.semibold))
                .padding(.horizontal)
            Text("How activity and heart health relate to sleep")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)

        ActivitySleepCorrelationView(
            sessions: visibleSessions,
            dailyCalories: filteredCalories
        )
        .padding(.horizontal)

        ActivitySleepContinuityCorrelationView(
            sessions: visibleSessions,
            dailyCalories: filteredCalories
        )
        .padding(.horizontal)

        HRVTrendView(
            dailyHRV: filteredHRV,
            sessions: visibleSessions
        )
        .padding(.horizontal)

        RestingHRSleepView(
            sessions: visibleSessions,
            dailyRestingHR: filteredRestingHR
        )
        .padding(.horizontal)

        SleepHRActivityView(
            sessions: visibleSessions,
            sleepHeartRates: store.sleepHeartRates,
            dailyCalories: filteredCalories
        )
        .padding(.horizontal)
    }

    private var filteredCalories: [DailyMetricSample] {
        TrendWindow.metrics(store.dailyCalories, range: range, zoom: effectiveZoom, endingAt: rangeEnd)
    }

    private var filteredRestingHR: [DailyMetricSample] {
        TrendWindow.metrics(store.dailyRestingHR, range: range, zoom: effectiveZoom, endingAt: rangeEnd)
    }

    private var filteredHRV: [DailyMetricSample] {
        TrendWindow.metrics(store.dailyHRV, range: range, zoom: effectiveZoom, endingAt: rangeEnd)
    }

    private var trendsExportURL: URL? {
        guard !visibleSessions.isEmpty else { return nil }
        return try? CSVExporter.trendsFile(
            sessions: visibleSessions,
            dailyCalories: filteredCalories,
            dailyRestingHR: filteredRestingHR,
            dailyHRV: filteredHRV,
            sleepHeartRates: store.sleepHeartRates
        ).writeTemporaryFile()
    }
}
