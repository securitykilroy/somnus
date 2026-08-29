import SwiftUI

struct MetricCardView: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct QualityCardView: View {
    let session: SleepSession

    var body: some View {
        let quality = session.dataQuality
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Data Quality")
                        .font(.headline)
                    Text(quality.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Gauge(value: quality.score) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(tint(for: quality.score))
                .frame(width: 54, height: 54)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                qualityPill("Samples", "\(quality.rawSampleCount)")
                qualityPill("Sources", "\(max(quality.sourceCount, 1))")
                qualityPill("Overlap", quality.overlapDuration.hoursAndMinutes)
                qualityPill("Unknown", quality.unknownSleepRatio.percentString)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func qualityPill(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.caption)
    }

    private func tint(for score: Double) -> Color {
        switch score {
        case 0.85...1: return .green
        case 0.65..<0.85: return .blue
        case 0.45..<0.65: return .orange
        default: return .red
        }
    }
}

struct InsightListView: View {
    let sessions: [SleepSession]

    var body: some View {
        let insights = SleepInsightEngine.insights(for: sessions)
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Signals")
                    .font(.headline)
                ForEach(insights, id: \.self) { insight in
                    Label(insight, systemImage: "waveform.path.ecg")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct AwakeEventListView: View {
    let session: SleepSession

    var body: some View {
        let events = session.awakeEvents
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Awake Events")
                            .font(.headline)
                        Text("\(session.movementConfirmedAwakeningCount) likely out of bed")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "figure.walk")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

                ForEach(events) { event in
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: event.isMovementConfirmed ? "figure.walk.circle.fill" : "bed.double.circle")
                            .foregroundStyle(event.isMovementConfirmed ? .orange : .secondary)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.classification.rawValue)
                                .font(.subheadline.bold())
                            Text("\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(event.duration.hoursAndMinutes)
                                .font(.subheadline.bold())
                            Text("\(Int(event.stepCount.rounded())) steps")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if event.id != events.last?.id {
                        Divider()
                    }
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct MorningWakeCardView: View {
    let session: SleepSession

    var body: some View {
        let analysis = session.morningWakeAnalysis()
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Early Morning")
                        .font(.headline)
                    Text("After \(analysis.cutoff.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: analysis.hasEarlyMorningWakePattern ? "sunrise.fill" : "sunrise")
                    .font(.title2)
                    .foregroundStyle(analysis.hasEarlyMorningWakePattern ? .orange : .secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metric("Tail", analysis.terminalWakeDuration.hoursAndMinutes, "final wake to get-up")
                metric("Awake/In Bed", analysis.awakeOrInBedAfterCutoff.hoursAndMinutes, "after cutoff")
                metric("Sleep After", analysis.sleepAfterCutoff.hoursAndMinutes, "after cutoff")
                metric("Out of Bed", "\(analysis.outOfBedEventCount)", analysis.outOfBedDuration.hoursAndMinutes)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func metric(_ title: String, _ value: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum SleepInsightEngine {
    static func insights(for sessions: [SleepSession]) -> [String] {
        guard let latest = sessions.first else { return [] }
        let sorted = sessions.sorted { $0.nightDate > $1.nightDate }
        let prior = Array(sorted.dropFirst().prefix(30))
        guard !prior.isEmpty else {
            return ["More nights will unlock personal baseline comparisons."]
        }

        let baselineSleep = prior.reduce(0) { $0 + $1.totalSleep } / Double(prior.count)
        let baselineWASO = prior.reduce(0) { $0 + $1.wakeAfterSleepOnset } / Double(prior.count)
        let baselineFragmentation = prior.reduce(0) { $0 + $1.fragmentationIndex } / Double(prior.count)

        var result: [String] = []
        let sleepDelta = latest.totalSleep - baselineSleep
        if abs(sleepDelta) >= 45 * 60 {
            result.append("Sleep duration was \(abs(sleepDelta).hoursAndMinutes) \(sleepDelta > 0 ? "above" : "below") your recent baseline.")
        }
        let wasoDelta = latest.wakeAfterSleepOnset - baselineWASO
        if abs(wasoDelta) >= 20 * 60 {
            result.append("Wake after sleep onset was \(abs(wasoDelta).hoursAndMinutes) \(wasoDelta > 0 ? "higher" : "lower") than usual.")
        }
        let fragDelta = latest.fragmentationIndex - baselineFragmentation
        if abs(fragDelta) >= 0.12 {
            result.append("Sleep continuity was \(fragDelta > 0 ? "more fragmented" : "steadier") than your 30-day pattern.")
        }
        if latest.dataQuality.score < 0.65 {
            result.append("This night has mixed data quality, so stage-level conclusions should be treated cautiously.")
        }
        if latest.movementConfirmedAwakeningCount > 0 {
            result.append("\(latest.movementConfirmedAwakeningCount) awake event\(latest.movementConfirmedAwakeningCount == 1 ? "" : "s") had movement evidence, suggesting likely out-of-bed time.")
        }
        let morning = latest.morningWakeAnalysis()
        if morning.terminalWakeDuration >= 20 * 60 {
            result.append("The final early-morning wake tail lasted \(morning.terminalWakeDuration.hoursAndMinutes).")
        } else if morning.awakeOrInBedAfterCutoff >= 30 * 60 {
            result.append("There was \(morning.awakeOrInBedAfterCutoff.hoursAndMinutes) awake or in-bed time after 4 AM.")
        }
        return result.isEmpty ? ["Last night was close to your recent baseline across duration and continuity."] : result
    }
}
