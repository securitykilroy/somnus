import SwiftUI

enum TrendRange: String, CaseIterable, Identifiable {
    case week        = "7D"
    case oneMonth    = "1M"
    case threeMonths = "3M"
    case sixMonths   = "6M"
    case year        = "1Y"
    case twoYears    = "2Y"
    case threeYears  = "3Y"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .week:        return 7
        case .oneMonth:    return 30
        case .threeMonths: return 90
        case .sixMonths:   return 180
        case .year:        return 365
        case .twoYears:    return 730
        case .threeYears:  return 1095
        }
    }

    var offset: DateComponents {
        switch self {
        case .week:
            return DateComponents(day: -7)
        case .oneMonth:
            return DateComponents(month: -1)
        case .threeMonths:
            return DateComponents(month: -3)
        case .sixMonths:
            return DateComponents(month: -6)
        case .year:
            return DateComponents(year: -1)
        case .twoYears:
            return DateComponents(year: -2)
        case .threeYears:
            return DateComponents(year: -3)
        }
    }
}

enum TrendZoom: String, CaseIterable, Identifiable {
    case all = "All"
    case year = "1Y"
    case sixMonths = "6M"
    case month = "30D"
    case twoWeeks = "14D"
    case week = "7D"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .all: return nil
        case .year: return 365
        case .sixMonths: return 180
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
        calendar.date(byAdding: range.offset, to: end) ?? end
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
    @Environment(SleepIntentStore.self) var intentStore
    @Environment(PeakAlphaStore.self) var peakAlphaStore
    @Environment(MealStore.self) var mealStore
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
                        RecoveryScoreTrendView(scores: recoveryScores)
                            .padding(.horizontal)
                        SleepDurationChartView(sessions: visibleSessions)
                            .padding(.horizontal)
                        SleepDebtChartView(sessions: visibleSessions)
                            .padding(.horizontal)
                        ContinuityChartView(sessions: visibleSessions)
                            .padding(.horizontal)
                        SleepLatencyTrendView(records: latencyRecords, summary: latencySummary)
                            .padding(.horizontal)
                        MorningWakeTrendView(sessions: visibleSessions)
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
                mealStore.reload()
                try? await intentStore.loadAsync()
                try? await peakAlphaStore.loadAsync()
                await store.load()
                publishLatencySnapshots()
            }
            .task {
                rangeEnd = Date()
                try? await peakAlphaStore.loadAsync()
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

    private var latencyRecords: [SleepLatencyRecord] {
        SleepLatencyAnalyzer.records(
            sessions: visibleSessions,
            events: intentStore.events
        )
    }

    private var latencySummary: SleepLatencySummary {
        SleepLatencyAnalyzer.summary(records: latencyRecords, now: rangeEnd)
    }

    private var recoveryScores: [RecoveryScore] {
        RecoveryScoreCalculator.scores(
            sessions: visibleSessions,
            dailyHRV: filteredHRV,
            dailyRestingHR: filteredRestingHR
        )
    }

    @ViewBuilder
    private var correlationsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Correlations")
                .font(.title3.weight(.semibold))
                .padding(.horizontal)
            Text("How activity, heart metrics, mindfulness, and Peak Alpha relate to sleep")
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

        ActivityToSleepStagesView(
            sessions: visibleSessions,
            dailyCalories: filteredCalories
        )
        .padding(.horizontal)

        SleepStagesToNextDayHRVView(
            sessions: visibleSessions,
            dailyHRV: filteredHRV
        )
        .padding(.horizontal)

        SleepStagesToNextDayRestingHRView(
            sessions: visibleSessions,
            dailyRestingHR: filteredRestingHR
        )
        .padding(.horizontal)

        MeditationToSleepView(
            sessions: visibleSessions,
            dailyMindfulMinutes: filteredMindfulMinutes,
            recoveryScores: recoveryScores
        )
        .padding(.horizontal)

        PeakAlphaCorrelationView(
            entries: filteredPeakAlphaEntries,
            sessions: visibleSessions,
            dailyMindfulMinutes: filteredMindfulMinutes,
            recoveryScores: recoveryScores
        )
        .padding(.horizontal)

        MealTimingSleepView(
            sessions: visibleSessions,
            meals: mealStore.events
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

    private var filteredMindfulMinutes: [DailyMetricSample] {
        TrendWindow.metrics(store.dailyMindfulMinutes, range: range, zoom: effectiveZoom, endingAt: rangeEnd)
    }

    private var filteredPeakAlphaEntries: [PeakAlphaEntry] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: TrendWindow.rangeStart(for: range, endingAt: rangeEnd))
        let end = calendar.startOfDay(for: rangeEnd)
        return peakAlphaStore.entries.filter { $0.day >= start && $0.day <= end }
    }

    private var trendsExportURL: URL? {
        guard !visibleSessions.isEmpty else { return nil }
        return try? CSVExporter.trendsFile(
            sessions: visibleSessions,
            dailyCalories: filteredCalories,
            dailyRestingHR: filteredRestingHR,
            dailyHRV: filteredHRV,
            sleepHeartRates: store.sleepHeartRates,
            meals: mealStore.events
        ).writeTemporaryFile()
    }

    private func publishLatencySnapshots() {
        let records = SleepLatencyAnalyzer.records(
            sessions: store.sessions,
            events: intentStore.events
        )
        try? intentStore.saveLatencySnapshots(from: records)
    }
}
