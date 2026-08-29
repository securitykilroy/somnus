import Foundation
import Testing
@testable import somnus

struct SleepAnalysisTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test func normalizerPreservesRawSamplesAndResolvesOverlaps() {
        let start = date("2026-05-01 22:00")
        let samples = [
            SleepStage(startDate: start, endDate: start.addingTimeInterval(2 * 3600), type: .core, sourceName: "Watch"),
            SleepStage(startDate: start.addingTimeInterval(3600), endDate: start.addingTimeInterval(3 * 3600), type: .deep, sourceName: "Phone"),
        ]

        let normalized = SleepTimelineNormalizer.normalize(samples)

        #expect(normalized.rawStages.count == 2)
        #expect(normalized.segments.count == 3)
        #expect(normalized.segments.map(\.type) == [.core, .deep, .deep])
        #expect(normalized.totalOverlap == 3600)
        #expect(normalized.duration(for: .core) == 3600)
        #expect(normalized.duration(for: .deep) == 7200)
    }

    @Test func unspecifiedSleepCountsAsSleepButNotCoreSleep() {
        let start = date("2026-05-01 23:00")
        let session = SleepSession(
            nightDate: calendar.startOfDay(for: start.addingTimeInterval(8 * 3600)),
            stages: [
                SleepStage(startDate: start, endDate: start.addingTimeInterval(3600), type: .asleepUnspecified),
                SleepStage(startDate: start.addingTimeInterval(3600), endDate: start.addingTimeInterval(3 * 3600), type: .core),
            ]
        )

        #expect(session.totalSleep == 3 * 3600)
        #expect(session.coreDuration == 2 * 3600)
        #expect(session.unspecifiedSleepDuration == 3600)
        #expect(session.dataQuality.unknownSleepRatio == 1.0 / 3.0)
    }

    @Test func sleepMetricsIncludeLatencyWasoAndFragmentation() {
        let start = date("2026-05-01 22:00")
        let session = SleepSession(
            nightDate: calendar.startOfDay(for: start.addingTimeInterval(9 * 3600)),
            stages: [
                SleepStage(startDate: start, endDate: start.addingTimeInterval(20 * 60), type: .inBed),
                SleepStage(startDate: start.addingTimeInterval(20 * 60), endDate: start.addingTimeInterval(2 * 3600), type: .core),
                SleepStage(startDate: start.addingTimeInterval(2 * 3600), endDate: start.addingTimeInterval(2.25 * 3600), type: .awake),
                SleepStage(startDate: start.addingTimeInterval(2.25 * 3600), endDate: start.addingTimeInterval(5 * 3600), type: .deep),
                SleepStage(startDate: start.addingTimeInterval(5 * 3600), endDate: start.addingTimeInterval(5.25 * 3600), type: .awake),
                SleepStage(startDate: start.addingTimeInterval(5.25 * 3600), endDate: start.addingTimeInterval(7 * 3600), type: .rem),
            ]
        )

        #expect(session.sleepLatency == 20 * 60)
        #expect(session.wakeAfterSleepOnset == 30 * 60)
        #expect(session.awakeningCount == 2)
        #expect(session.longestSleepBlock == 2.75 * 3600)
        #expect(session.fragmentationIndex > 0.1)
    }

    @Test func morningWakeAnalysisSeparatesFinalWakeTail() {
        let start = date("2026-05-01 22:30")
        let session = SleepSession(
            nightDate: calendar.startOfDay(for: start.addingTimeInterval(9 * 3600)),
            stages: [
                SleepStage(startDate: start, endDate: date("2026-05-02 04:05"), type: .core),
                SleepStage(startDate: date("2026-05-02 04:05"), endDate: date("2026-05-02 04:20"), type: .awake),
                SleepStage(startDate: date("2026-05-02 04:20"), endDate: date("2026-05-02 05:15"), type: .rem),
                SleepStage(startDate: date("2026-05-02 05:15"), endDate: date("2026-05-02 06:00"), type: .awake),
                SleepStage(startDate: date("2026-05-02 06:00"), endDate: date("2026-05-02 06:35"), type: .inBed),
            ],
            movementSamples: [
                MovementSample(
                    startDate: date("2026-05-02 04:08"),
                    endDate: date("2026-05-02 04:10"),
                    stepCount: 16,
                    distance: 10,
                    sourceName: "Watch"
                )
            ]
        )

        let analysis = session.morningWakeAnalysis(calendar: calendar)

        #expect(analysis.terminalWakeDuration == 80 * 60)
        #expect(analysis.awakeOrInBedAfterCutoff == 95 * 60)
        #expect(analysis.sleepAfterCutoff == 60 * 60)
        #expect(analysis.outOfBedEventCount == 1)
        #expect(analysis.hasEarlyMorningWakePattern)
    }

    @Test func trendSummaryCalculatesRollingBaselinesAndOutliers() {
        let start = date("2026-05-01 07:00")
        let sessions = (0..<10).map { offset in
            SleepSession(
                nightDate: calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: start))!,
                stages: [
                    SleepStage(
                        startDate: calendar.date(byAdding: .day, value: offset, to: start.addingTimeInterval(-8 * 3600))!,
                        endDate: calendar.date(byAdding: .day, value: offset, to: start.addingTimeInterval(offset == 8 ? -7 * 3600 : 0))!,
                        type: .core
                    )
                ]
            )
        }

        let summary = SleepTrendSummary(sessions: sessions, targetSleep: 8 * 3600)

        #expect(summary.sevenDayMean == 7 * 3600)
        #expect(summary.thirtyDayMean > 0)
        #expect(summary.outliers.count == 1)
        #expect(summary.outliers.first?.session.nightDate == sessions[8].nightDate)
    }

    @Test func trendOutlierIdentityIsStableAcrossRecomputation() throws {
        let start = date("2026-05-01 07:00")
        let sessions = (0..<10).map { offset in
            SleepSession(
                nightDate: calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: start))!,
                stages: [
                    SleepStage(
                        startDate: calendar.date(byAdding: .day, value: offset, to: start.addingTimeInterval(-8 * 3600))!,
                        endDate: calendar.date(byAdding: .day, value: offset, to: start.addingTimeInterval(offset == 8 ? -7 * 3600 : 0))!,
                        type: .core
                    )
                ]
            )
        }
        let summary = SleepTrendSummary(sessions: sessions, targetSleep: 8 * 3600)

        let first = try #require(summary.outliers.first)
        let second = try #require(summary.outliers.first)

        #expect(first.id == second.id)
    }

    @Test func dailyMetricSampleIdentityIsDerivedFromSampleDate() {
        let day = date("2026-05-01 00:00")
        let first = DailyMetricSample(date: day, value: 42)
        let second = DailyMetricSample(date: day, value: 42)

        #expect(first.id == second.id)
    }

    @Test func trendWindowFiltersRangeAgainstFixedEndDate() {
        let end = date("2026-05-27 12:00")
        let inside = SleepSession(
            nightDate: calendar.startOfDay(for: end.addingTimeInterval(-3 * 24 * 3600)),
            stages: [
                SleepStage(startDate: end.addingTimeInterval(-3 * 24 * 3600), endDate: end.addingTimeInterval(-3 * 24 * 3600 + 3600), type: .core)
            ]
        )
        let outside = SleepSession(
            nightDate: calendar.startOfDay(for: end.addingTimeInterval(-20 * 24 * 3600)),
            stages: [
                SleepStage(startDate: end.addingTimeInterval(-20 * 24 * 3600), endDate: end.addingTimeInterval(-20 * 24 * 3600 + 3600), type: .core)
            ]
        )

        let result = TrendWindow.sessions([outside, inside], range: .week, endingAt: end, calendar: calendar)

        #expect(result.map(\.id) == [inside.id])
    }

    @Test func trendWindowAppliesZoomAfterRangeFiltering() {
        let end = date("2026-05-27 12:00")
        let sessions = [40, 20, 5].map { daysAgo in
            let start = end.addingTimeInterval(TimeInterval(-daysAgo * 24 * 3600))
            return SleepSession(
                nightDate: calendar.startOfDay(for: start),
                stages: [
                    SleepStage(startDate: start, endDate: start.addingTimeInterval(3600), type: .core)
                ]
            )
        }

        let ranged = TrendWindow.sessions(sessions, range: .threeMonths, endingAt: end, calendar: calendar)
        let visible = TrendWindow.visibleSessions(ranged, zoom: .month, endingAt: end, calendar: calendar)

        #expect(visible.map(\.nightDate) == sessions.dropFirst().map(\.nightDate).sorted())
    }

    @Test func trendWindowSupportsThreeYearRange() {
        let end = date("2026-05-27 12:00")
        let inside = SleepSession(
            nightDate: calendar.startOfDay(for: calendar.date(byAdding: .year, value: -2, to: end)!),
            stages: [
                SleepStage(
                    startDate: calendar.date(byAdding: .year, value: -2, to: end)!,
                    endDate: calendar.date(byAdding: .year, value: -2, to: end)!.addingTimeInterval(3600),
                    type: .core
                )
            ]
        )
        let outside = SleepSession(
            nightDate: calendar.startOfDay(for: calendar.date(byAdding: .year, value: -4, to: end)!),
            stages: [
                SleepStage(
                    startDate: calendar.date(byAdding: .year, value: -4, to: end)!,
                    endDate: calendar.date(byAdding: .year, value: -4, to: end)!.addingTimeInterval(3600),
                    type: .core
                )
            ]
        )

        let result = TrendWindow.sessions([outside, inside], range: .threeYears, endingAt: end, calendar: calendar)

        #expect(result.map(\.id) == [inside.id])
    }

    @Test func trendWindowCanZoomLongRangesToOneYear() {
        let end = date("2026-05-27 12:00")
        let sessions = [700, 300].map { daysAgo in
            let start = end.addingTimeInterval(TimeInterval(-daysAgo * 24 * 3600))
            return SleepSession(
                nightDate: calendar.startOfDay(for: start),
                stages: [
                    SleepStage(startDate: start, endDate: start.addingTimeInterval(3600), type: .core)
                ]
            )
        }

        let ranged = TrendWindow.sessions(sessions, range: .threeYears, endingAt: end, calendar: calendar)
        let visible = TrendWindow.visibleSessions(ranged, zoom: .year, endingAt: end, calendar: calendar)

        #expect(visible.map(\.id) == [sessions[1].id])
    }

    @Test func sleepHeartRateAveragesUsePrecomputedSessionWindows() {
        let firstStart = date("2026-05-01 22:00")
        let secondStart = date("2026-05-02 22:00")
        let sessions = [firstStart, secondStart].map { start in
            SleepSession(
                nightDate: calendar.startOfDay(for: start.addingTimeInterval(8 * 3600)),
                stages: [
                    SleepStage(startDate: start, endDate: start.addingTimeInterval(8 * 3600), type: .core)
                ]
            )
        }
        let samples = [
            HealthKitManager.TimedQuantitySample(startDate: firstStart.addingTimeInterval(-60), value: 50),
            HealthKitManager.TimedQuantitySample(startDate: firstStart.addingTimeInterval(60), value: 60),
            HealthKitManager.TimedQuantitySample(startDate: firstStart.addingTimeInterval(120), value: 80),
            HealthKitManager.TimedQuantitySample(startDate: firstStart.addingTimeInterval(8 * 3600), value: 200),
            HealthKitManager.TimedQuantitySample(startDate: secondStart.addingTimeInterval(60), value: 55),
            HealthKitManager.TimedQuantitySample(startDate: secondStart.addingTimeInterval(120), value: 65),
        ]

        let averages = HealthKitManager.averageSamplesBySession(samples: samples, sessions: sessions)

        #expect(averages[sessions[0].nightDate] == 70)
        #expect(averages[sessions[1].nightDate] == 60)
    }

    @Test func activityContinuityCorrelationPairsPreviousDayCaloriesWithWaso() {
        let bedStart = date("2026-05-02 22:00")
        let session = SleepSession(
            nightDate: calendar.startOfDay(for: bedStart.addingTimeInterval(8 * 3600)),
            stages: [
                SleepStage(startDate: bedStart, endDate: bedStart.addingTimeInterval(2 * 3600), type: .core),
                SleepStage(startDate: bedStart.addingTimeInterval(2 * 3600), endDate: bedStart.addingTimeInterval(2.25 * 3600), type: .awake),
                SleepStage(startDate: bedStart.addingTimeInterval(2.25 * 3600), endDate: bedStart.addingTimeInterval(8 * 3600), type: .core),
            ]
        )
        let previousDay = calendar.startOfDay(for: bedStart)
        let calories = [
            DailyMetricSample(date: previousDay, value: 725),
            DailyMetricSample(date: calendar.date(byAdding: .day, value: -1, to: previousDay)!, value: 100),
        ]

        let points = ActivitySleepContinuityCorrelationView.points(
            sessions: [session],
            dailyCalories: calories,
            calendar: calendar
        )

        #expect(points.count == 1)
        #expect(points.first?.calories == 725)
        #expect(points.first?.wasoMinutes == 15)
    }

    @Test func trendsCSVExportsVisibleSessionAndMetricData() {
        let start = date("2026-05-02 22:00")
        let session = SleepSession(
            nightDate: calendar.startOfDay(for: start.addingTimeInterval(8 * 3600)),
            stages: [
                SleepStage(startDate: start, endDate: start.addingTimeInterval(2 * 3600), type: .core),
                SleepStage(startDate: start.addingTimeInterval(2 * 3600), endDate: start.addingTimeInterval(2.25 * 3600), type: .awake),
                SleepStage(startDate: start.addingTimeInterval(2.25 * 3600), endDate: start.addingTimeInterval(8 * 3600), type: .deep),
            ],
            movementSamples: [
                MovementSample(
                    startDate: start.addingTimeInterval(2 * 3600 + 60),
                    endDate: start.addingTimeInterval(2 * 3600 + 180),
                    stepCount: 12,
                    distance: 8,
                    sourceName: "Watch"
                )
            ]
        )
        let caloriesDate = calendar.startOfDay(for: start)

        let file = CSVExporter.trendsFile(
            sessions: [session],
            dailyCalories: [DailyMetricSample(date: caloriesDate, value: 650)],
            dailyRestingHR: [DailyMetricSample(date: session.nightDate, value: 55)],
            dailyHRV: [DailyMetricSample(date: session.nightDate, value: 42)],
            sleepHeartRates: [session.nightDate: 58],
            calendar: calendar
        )

        #expect(file.filename == "somnus-trends-2026-05-03-to-2026-05-03.csv")
        #expect(file.content.contains("night_date,bedtime,wake_time,total_sleep_minutes"))
        #expect(file.content.contains("2026-05-03"))
        #expect(file.content.contains(",650,55,42,58"))
        #expect(file.content.contains(",15,1,1,15,"))
    }

    @Test func dailyCSVExportsSummaryTimelineAwakeEventsAndMovement() {
        let start = date("2026-05-02 22:00")
        let session = SleepSession(
            nightDate: calendar.startOfDay(for: start.addingTimeInterval(8 * 3600)),
            stages: [
                SleepStage(startDate: start, endDate: start.addingTimeInterval(2 * 3600), type: .core, sourceName: "Watch"),
                SleepStage(startDate: start.addingTimeInterval(2 * 3600), endDate: start.addingTimeInterval(2.25 * 3600), type: .awake, sourceName: "Watch"),
                SleepStage(startDate: start.addingTimeInterval(2.25 * 3600), endDate: start.addingTimeInterval(8 * 3600), type: .rem, sourceName: "Watch"),
            ],
            movementSamples: [
                MovementSample(
                    startDate: start.addingTimeInterval(2 * 3600 + 60),
                    endDate: start.addingTimeInterval(2 * 3600 + 180),
                    stepCount: 12,
                    distance: 8,
                    standHourCount: 1,
                    sourceName: "Watch"
                )
            ]
        )

        let file = CSVExporter.dailyFile(for: session, calendar: calendar)

        #expect(file.filename == "somnus-daily-2026-05-03.csv")
        #expect(file.content.contains("record_type,night_date,start,end,duration_minutes,metric,value,unit,stage_type,classification,confidence,steps,distance_meters,stand_hours,source"))
        #expect(file.content.contains("summary,2026-05-03,,,465,total_sleep,465,minutes"))
        #expect(file.content.contains("stage,2026-05-03,2026-05-02T22:00:00Z,2026-05-03T00:00:00Z,120,,,,Core"))
        #expect(file.content.contains("awake_event,2026-05-03,2026-05-03T00:00:00Z,2026-05-03T00:15:00Z,15,,,,,Likely Out of Bed"))
        #expect(file.content.contains("movement,2026-05-03,2026-05-03T00:01:00Z,2026-05-03T00:03:00Z,2,,,,,,,12,8,1,Watch"))
    }

    @MainActor
    @Test func metricsFetchWindowDoesNotExpandPastThreeYearsForLongHistory() {
        let now = date("2026-05-27 12:00")
        let oldStart = date("2021-01-01 23:00")
        let session = SleepSession(
            nightDate: calendar.startOfDay(for: oldStart.addingTimeInterval(8 * 3600)),
            stages: [
                SleepStage(startDate: oldStart, endDate: oldStart.addingTimeInterval(8 * 3600), type: .core)
            ]
        )

        let window = SleepStore.metricsFetchWindow(for: [session], end: now, calendar: calendar)

        #expect(window.start == calendar.date(byAdding: .year, value: -3, to: now)!)
        #expect(window.end == now)
    }

    @MainActor
    @Test func foregroundRefreshReloadsOnlyOnceLastLoadIsStale() {
        let now = date("2026-05-27 06:00")

        // Never loaded: always reload.
        #expect(SleepStore.shouldReload(lastLoadedAt: nil, now: now, minimumInterval: 60))

        // A momentary trip through Control Center should not refetch the
        // entire sleep history.
        #expect(!SleepStore.shouldReload(
            lastLoadedAt: now.addingTimeInterval(-15),
            now: now,
            minimumInterval: 60
        ))

        // A real return to the app after the watch has had time to sync.
        #expect(SleepStore.shouldReload(
            lastLoadedAt: now.addingTimeInterval(-90),
            now: now,
            minimumInterval: 60
        ))

        // Exactly at the boundary counts as stale.
        #expect(SleepStore.shouldReload(
            lastLoadedAt: now.addingTimeInterval(-60),
            now: now,
            minimumInterval: 60
        ))

        // A backwards clock jump must not pin the store into a stale state.
        #expect(SleepStore.shouldReload(
            lastLoadedAt: now.addingTimeInterval(3600),
            now: now,
            minimumInterval: 60
        ))
    }

    @Test func regularityAnchorIsMidpointOfSleepOnsetAndFinalWake() {
        let start = date("2026-05-01 23:00")
        // Sleep onset at 23:30, final sleep ends at 06:00 — a long mid-sleep
        // awakening should not drag the anchor away from that midpoint (02:45).
        let session = SleepSession(
            nightDate: calendar.startOfDay(for: start.addingTimeInterval(9 * 3600)),
            stages: [
                SleepStage(startDate: start, endDate: start.addingTimeInterval(30 * 60), type: .inBed),
                SleepStage(startDate: start.addingTimeInterval(30 * 60), endDate: date("2026-05-02 02:00"), type: .core),
                SleepStage(startDate: date("2026-05-02 02:00"), endDate: date("2026-05-02 03:00"), type: .awake),
                SleepStage(startDate: date("2026-05-02 03:00"), endDate: date("2026-05-02 06:00"), type: .rem),
            ]
        )

        #expect(session.regularityAnchor == date("2026-05-02 02:45"))
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }
}
