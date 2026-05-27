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

struct TrendsView: View {
    @Environment(SleepStore.self) var store
    @State private var range: TrendRange = .week
    @State private var zoom: TrendZoom = .all

    private var rangeEnd: Date { Date() }
    private var rangeStart: Date {
        Calendar.current.date(byAdding: .day, value: -range.days, to: rangeEnd)!
    }

    private var sessions: [SleepSession] {
        store.sessions(in: rangeStart...rangeEnd).sorted { $0.nightDate < $1.nightDate }
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
                    } else if sessions.isEmpty {
                        ContentUnavailableView(
                            "No Data",
                            systemImage: "chart.xyaxis.line",
                            description: Text("No sleep data in the selected time range.")
                        )
                    } else {
                        let summary = SleepTrendSummary(sessions: sessions, targetSleep: 8 * 3600)

                        TrendSummaryView(summary: summary)
                            .padding(.horizontal)
                        SleepDurationChartView(sessions: sessions, visibleDays: visibleDays)
                            .padding(.horizontal)
                        SleepDebtChartView(sessions: sessions, visibleDays: visibleDays)
                            .padding(.horizontal)
                        ContinuityChartView(sessions: sessions, visibleDays: visibleDays)
                            .padding(.horizontal)
                        MovementWakeChartView(sessions: sessions, visibleDays: visibleDays)
                            .padding(.horizontal)
                        RegularityChartView(sessions: sessions, visibleDays: visibleDays)
                            .padding(.horizontal)
                        StageBreakdownChartView(sessions: sessions, visibleDays: visibleDays)
                            .padding(.horizontal)
                        StagePercentageChartView(sessions: sessions, visibleDays: visibleDays)
                            .padding(.horizontal)
                        OutlierListView(outliers: summary.outliers)
                            .padding(.horizontal)

                        correlationsSection
                    }
                }
                .padding(.vertical)
            }
            .refreshable { await store.load() }
            .navigationTitle("Trends")
        }
    }

    private var visibleDays: Int? {
        range.days <= 30 ? nil : zoom.days
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
            sessions: sessions,
            dailyCalories: filteredCalories
        )
        .padding(.horizontal)

        HRVTrendView(
            dailyHRV: filteredHRV,
            sessions: sessions
        )
        .padding(.horizontal)

        RestingHRSleepView(
            sessions: sessions,
            dailyRestingHR: filteredRestingHR
        )
        .padding(.horizontal)

        SleepHRActivityView(
            sessions: sessions,
            sleepHeartRates: store.sleepHeartRates,
            dailyCalories: filteredCalories
        )
        .padding(.horizontal)
    }

    private var filteredCalories: [DailyMetricSample] {
        store.dailyCalories.filter { $0.date >= rangeStart && $0.date <= rangeEnd }
    }

    private var filteredRestingHR: [DailyMetricSample] {
        store.dailyRestingHR.filter { $0.date >= rangeStart && $0.date <= rangeEnd }
    }

    private var filteredHRV: [DailyMetricSample] {
        store.dailyHRV.filter { $0.date >= rangeStart && $0.date <= rangeEnd }
    }
}
