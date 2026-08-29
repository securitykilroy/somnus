import SwiftUI

struct OverviewView: View {
    @Environment(SleepStore.self) var store
    @Environment(SleepIntentStore.self) var intentStore
    @Environment(PeakAlphaStore.self) var peakAlphaStore

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading {
                    ProgressView("Loading sleep data...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = store.error {
                    ContentUnavailableView(
                        "Unable to Load Data",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error.localizedDescription)
                    )
                } else if let session = store.lastNight {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            lastNightHeader(session)
                            RecoveryScoreCardView(score: lastNightRecoveryScore)
                            SleepIntentCaptureCard()
                            PeakAlphaCaptureCard()
                            MealLogCard()
                            InsightListView(sessions: store.sessions)
                            debtSection(session)
                            continuitySection(session)
                            MorningWakeCardView(session: session)
                            QualityCardView(session: session)
                            weekSummarySection
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .refreshable {
                        try? intentStore.load()
                        try? await peakAlphaStore.loadAsync()
                        await store.load()
                    }
                } else {
                    ContentUnavailableView(
                        "No Sleep Data",
                        systemImage: "moon.zzz",
                        description: Text("Sleep data from Apple Health will appear here.")
                    )
                }
            }
            .navigationTitle("Overview")
            .task {
                try? await peakAlphaStore.loadAsync()
            }
        }
    }

    @ViewBuilder
    private func lastNightHeader(_ session: SleepSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.nightDate, style: .date)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(session.totalSleep.hoursAndMinutes)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                Text("total sleep")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
            }

            stageDurations(session)

            HStack(spacing: 16) {
                Label("\(Int(session.efficiency * 100))% efficiency", systemImage: "bed.double.fill")
                Label("\(session.startTime.formatted(date: .omitted, time: .shortened)) – \(session.endTime.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private struct StageDuration: Identifiable {
        var id: String { type.rawValue }
        let type: SleepStageType
        let duration: TimeInterval
        /// Share of total sleep. `nil` for awake time, which is not part of
        /// total sleep and so has no meaningful percentage.
        let share: Double?

        /// `SleepStageType.rawValue` is "Unspecified Sleep", too long for a
        /// column this narrow.
        var label: String {
            type == .asleepUnspecified ? "Asleep" : type.rawValue
        }
    }

    private func stageBreakdown(_ session: SleepSession) -> [StageDuration] {
        let total = session.totalSleep
        func share(_ duration: TimeInterval) -> Double? {
            total > 0 ? duration / total : nil
        }

        return [
            StageDuration(type: .deep, duration: session.deepDuration, share: share(session.deepDuration)),
            StageDuration(type: .rem, duration: session.remDuration, share: share(session.remDuration)),
            StageDuration(type: .core, duration: session.coreDuration, share: share(session.coreDuration)),
            StageDuration(
                type: .asleepUnspecified,
                duration: session.unspecifiedSleepDuration,
                share: share(session.unspecifiedSleepDuration)
            ),
            StageDuration(type: .awake, duration: session.awakeDuration, share: nil),
        ].filter { $0.duration > 0 }
    }

    /// Plain text rather than a chart — the numbers are the point, and this
    /// cannot be clipped or collapsed by chart layout on a narrow screen.
    @ViewBuilder
    private func stageDurations(_ session: SleepSession) -> some View {
        let stages = stageBreakdown(session)
        if !stages.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                ForEach(stages) { stage in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(stage.type.color)
                                .frame(width: 7, height: 7)
                            Text(stage.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(stage.duration.hoursAndMinutes)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if let share = stage.share {
                            Text(share.percentString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    // Equal shares of the row, so four stages cannot push each
                    // other off the edge on a narrow iPhone.
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func debtSection(_ session: SleepSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last Night's Sleep Debt")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                DebtCardView(title: "vs 8 hours", debt: 8 * 3600 - session.totalSleep)
                DebtCardView(title: "vs 7 hours", debt: 7 * 3600 - session.totalSleep)
                DebtCardView(
                    title: "vs your mean",
                    subtitle: store.lifetimeMean.hoursAndMinutes,
                    debt: store.lifetimeMean - session.totalSleep
                )
                DebtCardView(
                    title: "vs your median",
                    subtitle: store.lifetimeMedian.hoursAndMinutes,
                    debt: store.lifetimeMedian - session.totalSleep
                )
            }
        }
    }

    @ViewBuilder
    private func continuitySection(_ session: SleepSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continuity")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricCardView(
                    title: "Awakenings",
                    value: "\(session.awakeningCount)",
                    subtitle: "after sleep onset"
                )
                MetricCardView(
                    title: "Out of Bed",
                    value: "\(session.movementConfirmedAwakeningCount)",
                    subtitle: session.likelyOutOfBedDuration.hoursAndMinutes,
                    valueColor: session.movementConfirmedAwakeningCount > 0 ? .orange : .primary
                )
                MetricCardView(
                    title: "WASO",
                    value: session.wakeAfterSleepOnset.hoursAndMinutes,
                    subtitle: "awake after sleep onset"
                )
                MetricCardView(
                    title: "Longest Block",
                    value: session.longestSleepBlock.hoursAndMinutes,
                    subtitle: "uninterrupted sleep"
                )
                MetricCardView(
                    title: "Morning Tail",
                    value: session.morningWakeAnalysis().terminalWakeDuration.hoursAndMinutes,
                    subtitle: "final wake to get-up",
                    valueColor: session.morningWakeAnalysis().terminalWakeDuration >= 20 * 60 ? .orange : .primary
                )
                MetricCardView(
                    title: "Fragmentation",
                    value: session.fragmentationIndex.percentString,
                    subtitle: "\(session.transitionCount) stage changes",
                    valueColor: session.fragmentationIndex > 0.45 ? .orange : .primary
                )
            }
        }
    }

    @ViewBuilder
    private var weekSummarySection: some View {
        let weekSessions = store.sessions(in: sevenDayRange)
        if !weekSessions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Last 7 Days")
                    .font(.headline)

                let totalDebt8h  = weekSessions.reduce(0.0) { $0 + max(0, 8 * 3600 - $1.totalSleep) }
                let totalDebt7h  = weekSessions.reduce(0.0) { $0 + max(0, 7 * 3600 - $1.totalSleep) }
                let meanSleep    = weekSessions.reduce(0.0) { $0 + $1.totalSleep } / Double(weekSessions.count)
                let meanDebt8h   = totalDebt8h / Double(weekSessions.count)
                let meanEfficiency = weekSessions.reduce(0.0) { $0 + $1.efficiency } / Double(weekSessions.count)
                let meanFragmentation = weekSessions.reduce(0.0) { $0 + $1.fragmentationIndex } / Double(weekSessions.count)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SummaryStatCard(title: "Total Debt vs 8h", value: totalDebt8h.hoursAndMinutes, valueColor: .red)
                    SummaryStatCard(title: "Total Debt vs 7h", value: totalDebt7h.hoursAndMinutes, valueColor: .red)
                    SummaryStatCard(title: "Mean Sleep", value: meanSleep.hoursAndMinutes)
                    SummaryStatCard(title: "Mean Debt vs 8h", value: meanDebt8h.hoursAndMinutes, valueColor: .red)
                    SummaryStatCard(title: "Mean Efficiency", value: meanEfficiency.percentString)
                    SummaryStatCard(title: "Fragmentation", value: meanFragmentation.percentString)
                }
            }
        }
    }

    private var lastNightRecoveryScore: RecoveryScore? {
        RecoveryScoreCalculator.scores(
            sessions: store.sessions,
            dailyHRV: store.dailyHRV,
            dailyRestingHR: store.dailyRestingHR
        ).first
    }

    private var sevenDayRange: ClosedRange<Date> {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: end)!
        return start...end
    }
}
