import Foundation

nonisolated struct SleepSession: Identifiable {
    let id: UUID
    let nightDate: Date
    let stages: [SleepStage]
    let movementSamples: [MovementSample]
    let normalizedTimeline: NormalizedSleepTimeline
    let startTime: Date
    let endTime: Date
    let timeInBed: TimeInterval

    /// Detected once here rather than on each read. Every one of the
    /// out-of-bed readouts used to re-run the detector, and the trend charts
    /// read several of them per night inside a `ForEach` that SwiftUI
    /// re-evaluates on every layout pass.
    let awakeEvents: [AwakeEvent]

    /// Single-pass walks of the timeline, likewise hoisted out of the
    /// per-render path.
    let wakeAfterSleepOnset: TimeInterval
    let awakeningCount: Int
    let transitionCount: Int
    let longestSleepBlock: TimeInterval

    init(nightDate: Date, stages: [SleepStage], movementSamples: [MovementSample] = []) {
        let timeline = SleepTimelineNormalizer.normalize(stages)
        let start = stages.min(by: { $0.startDate < $1.startDate })?.startDate ?? nightDate
        let end = stages.max(by: { $0.endDate < $1.endDate })?.endDate ?? nightDate

        self.id = Self.identifier(forNight: nightDate)
        self.nightDate = nightDate
        self.stages = stages
        self.movementSamples = movementSamples
        self.normalizedTimeline = timeline
        self.startTime = start
        self.endTime = end
        self.timeInBed = stages.isEmpty ? 0 : end.timeIntervalSince(start)
        self.awakeEvents = AwakeEventDetector.events(
            timeline: timeline,
            movementSamples: movementSamples
        )

        let derived = Self.timelineMetrics(timeline)
        self.wakeAfterSleepOnset = derived.wakeAfterSleepOnset
        self.awakeningCount = derived.awakeningCount
        self.transitionCount = derived.transitionCount
        self.longestSleepBlock = derived.longestSleepBlock
    }

    /// Copies a session with new movement samples, reusing the already-computed
    /// timeline and its derived metrics — only the awake events depend on
    /// movement evidence, so only they are recomputed.
    init(copying original: SleepSession, movementSamples: [MovementSample]) {
        self.id = original.id
        self.nightDate = original.nightDate
        self.stages = original.stages
        self.movementSamples = movementSamples
        self.normalizedTimeline = original.normalizedTimeline
        self.startTime = original.startTime
        self.endTime = original.endTime
        self.timeInBed = original.timeInBed
        self.awakeEvents = AwakeEventDetector.events(
            timeline: original.normalizedTimeline,
            movementSamples: movementSamples
        )
        self.wakeAfterSleepOnset = original.wakeAfterSleepOnset
        self.awakeningCount = original.awakeningCount
        self.transitionCount = original.transitionCount
        self.longestSleepBlock = original.longestSleepBlock
    }

    /// Derived from the night rather than random.
    ///
    /// A fresh `UUID()` per initialisation meant every reload handed SwiftUI a
    /// completely new set of identities, so `ForEach` tore down and rebuilt
    /// every row and chart mark even when nothing about the night had changed.
    private static func identifier(forNight nightDate: Date) -> UUID {
        let day = Int64((nightDate.timeIntervalSince1970 / 86_400).rounded(.down))
        let suffix = String(format: "%012llx", UInt64(bitPattern: day) & 0xFFFF_FFFF_FFFF)
        return UUID(uuidString: "506d6e75-0000-4000-8000-\(suffix)") ?? UUID()
    }

    private static func timelineMetrics(
        _ timeline: NormalizedSleepTimeline
    ) -> (
        wakeAfterSleepOnset: TimeInterval,
        awakeningCount: Int,
        transitionCount: Int,
        longestSleepBlock: TimeInterval
    ) {
        var waso: TimeInterval = 0
        var awakenings = 0
        var transitions = 0
        var longest: TimeInterval = 0
        var current: TimeInterval = 0
        var previousType: SleepStageType?
        /// End of the awake segment just counted, so a run of touching awake
        /// segments counts as one awakening.
        var openAwakeEnd: Date?

        let firstSleep = timeline.firstSleepStart
        let lastSleep = timeline.lastSleepEnd

        for segment in timeline.segments {
            if let previousType, previousType != segment.type { transitions += 1 }
            previousType = segment.type

            if segment.type.isSleep {
                current += segment.duration
                longest = max(longest, current)
            } else {
                current = 0
            }

            guard segment.type == .awake else {
                openAwakeEnd = nil
                continue
            }

            guard let firstSleep, let lastSleep,
                  segment.startDate >= firstSleep,
                  segment.endDate <= lastSleep else {
                openAwakeEnd = nil
                continue
            }

            waso += segment.duration
            // The timeline splits at every sample edge, so one continuous
            // awakening arrives as several segments whenever the watch wrote it
            // as consecutive samples, or an overlapping in-bed sample
            // introduced an edge part-way through. Counting segments read one
            // awakening as several; counting runs does not. Durations were
            // never affected, only the count.
            if openAwakeEnd != segment.startDate {
                awakenings += 1
            }
            openAwakeEnd = segment.endDate
        }

        return (waso, awakenings, transitions, longest)
    }

    var totalSleep: TimeInterval {
        normalizedTimeline.sleepDuration
    }

    var coreDuration: TimeInterval {
        normalizedTimeline.duration(for: .core)
    }

    var deepDuration: TimeInterval {
        normalizedTimeline.duration(for: .deep)
    }

    var remDuration: TimeInterval {
        normalizedTimeline.duration(for: .rem)
    }

    var awakeDuration: TimeInterval {
        normalizedTimeline.duration(for: .awake)
    }

    var unspecifiedSleepDuration: TimeInterval {
        normalizedTimeline.duration(for: .asleepUnspecified)
    }

    var efficiency: Double {
        guard timeInBed > 0 else { return 0 }
        return totalSleep / timeInBed
    }

    var stageSleepDuration: TimeInterval {
        coreDuration + deepDuration + remDuration
    }

    var deepRatio: Double {
        guard totalSleep > 0 else { return 0 }
        return deepDuration / totalSleep
    }

    var remRatio: Double {
        guard totalSleep > 0 else { return 0 }
        return remDuration / totalSleep
    }

    var coreRatio: Double {
        guard totalSleep > 0 else { return 0 }
        return coreDuration / totalSleep
    }

    var sleepLatency: TimeInterval {
        guard let bedStart = stages
            .filter({ $0.type == .inBed || $0.type == .awake })
            .min(by: { $0.startDate < $1.startDate })?.startDate,
            let firstSleep = normalizedTimeline.firstSleepStart,
            firstSleep > bedStart else { return 0 }
        return firstSleep.timeIntervalSince(bedStart)
    }

    var remLatency: TimeInterval? {
        guard let firstSleep = normalizedTimeline.firstSleepStart,
              let firstREM = normalizedTimeline.segments.first(where: { $0.type == .rem })?.startDate else {
            return nil
        }
        return max(0, firstREM.timeIntervalSince(firstSleep))
    }

    var fragmentationIndex: Double {
        guard totalSleep > 0 else { return 0 }
        let transitionRate = Double(transitionCount) / max(totalSleep.asHours, 0.1)
        let awakeningRate = Double(awakeningCount) / max(totalSleep.asHours, 0.1)
        let wasoRatio = wakeAfterSleepOnset / max(totalSleep, 1)
        return min(1, wasoRatio + (transitionRate * 0.04) + (awakeningRate * 0.08))
    }

    /// The clock-time midpoint between sleep onset and final wake — the standard
    /// "sleep midpoint" used to measure bedtime/wake-time regularity. Using the
    /// onset/wake midpoint (rather than `startTime + totalSleep / 2`) keeps the
    /// anchor stable across nights with long mid-sleep awakenings, since adding
    /// half of total *sleep* duration to the start time drifts earlier as awake
    /// gaps grow.
    var regularityAnchor: Date {
        guard let firstSleep = normalizedTimeline.firstSleepStart,
              let lastSleep = normalizedTimeline.lastSleepEnd else {
            return Date(timeIntervalSince1970: startTime.timeIntervalSince1970 + totalSleep / 2)
        }
        let midpoint = (firstSleep.timeIntervalSince1970 + lastSleep.timeIntervalSince1970) / 2
        return Date(timeIntervalSince1970: midpoint)
    }

    var dataQuality: SleepDataQuality {
        SleepDataQuality(session: self, timeline: normalizedTimeline)
    }

    var movementConfirmedAwakeningCount: Int {
        awakeEvents.filter(\.isMovementConfirmed).count
    }

    var likelyOutOfBedDuration: TimeInterval {
        awakeEvents
            .filter(\.isMovementConfirmed)
            .reduce(0) { $0 + $1.duration }
    }

    func morningWakeAnalysis(cutoffHour: Int = 4, calendar: Calendar = .current) -> MorningWakeAnalysis {
        let dayStart = calendar.startOfDay(for: nightDate)
        let cutoff = calendar.date(byAdding: .hour, value: cutoffHour, to: dayStart) ?? dayStart
        let segmentsAfterCutoff = normalizedTimeline.segments
            .filter { $0.endDate > cutoff && $0.startDate < endTime }

        let awakeOrInBedAfterCutoff = segmentsAfterCutoff
            .filter { !$0.type.isSleep }
            .reduce(0) { total, segment in
                total + clippedDuration(segment, from: cutoff, to: endTime)
            }

        let sleepAfterCutoff = segmentsAfterCutoff
            .filter { $0.type.isSleep }
            .reduce(0) { total, segment in
                total + clippedDuration(segment, from: cutoff, to: endTime)
            }

        let firstWakeAfterCutoff = segmentsAfterCutoff
            .filter { !$0.type.isSleep }
            .map { max($0.startDate, cutoff) }
            .min()

        let terminalWakeStart: Date?
        if let lastSleepEnd = normalizedTimeline.lastSleepEnd, lastSleepEnd < endTime {
            terminalWakeStart = max(lastSleepEnd, cutoff)
        } else {
            terminalWakeStart = nil
        }

        let terminalWakeDuration = terminalWakeStart.map { max(0, endTime.timeIntervalSince($0)) } ?? 0
        let outOfBedEvents = awakeEvents.filter { $0.endDate > cutoff }

        return MorningWakeAnalysis(
            cutoff: cutoff,
            firstWakeAfterCutoff: firstWakeAfterCutoff,
            terminalWakeStart: terminalWakeStart,
            terminalWakeDuration: terminalWakeDuration,
            awakeOrInBedAfterCutoff: awakeOrInBedAfterCutoff,
            sleepAfterCutoff: sleepAfterCutoff,
            outOfBedEventCount: outOfBedEvents.filter(\.isMovementConfirmed).count,
            outOfBedDuration: outOfBedEvents.filter(\.isMovementConfirmed).reduce(0) { $0 + $1.duration }
        )
    }

    private func clippedDuration(_ segment: SleepTimelineSegment, from start: Date, to end: Date) -> TimeInterval {
        let clippedStart = max(segment.startDate, start)
        let clippedEnd = min(segment.endDate, end)
        return max(0, clippedEnd.timeIntervalSince(clippedStart))
    }
}

nonisolated struct MorningWakeAnalysis {
    let cutoff: Date
    let firstWakeAfterCutoff: Date?
    let terminalWakeStart: Date?
    let terminalWakeDuration: TimeInterval
    let awakeOrInBedAfterCutoff: TimeInterval
    let sleepAfterCutoff: TimeInterval
    let outOfBedEventCount: Int
    let outOfBedDuration: TimeInterval

    var hasEarlyMorningWakePattern: Bool {
        terminalWakeDuration >= 20 * 60
            || awakeOrInBedAfterCutoff >= 30 * 60
            || outOfBedEventCount > 0
    }
}

nonisolated struct SleepDataQuality {
    let rawSampleCount: Int
    let sourceCount: Int
    let overlapDuration: TimeInterval
    let gapDuration: TimeInterval
    let conflictCount: Int
    let unknownSleepRatio: Double
    let score: Double

    init(session: SleepSession, timeline: NormalizedSleepTimeline) {
        rawSampleCount = timeline.rawStages.count
        sourceCount = Set(timeline.rawStages.compactMap(\.sourceName)).count
        overlapDuration = timeline.totalOverlap
        gapDuration = timeline.totalGap
        conflictCount = timeline.conflictingSegmentCount

        let unknown = timeline.duration(for: .asleepUnspecified)
        unknownSleepRatio = timeline.sleepDuration > 0 ? unknown / timeline.sleepDuration : 0

        var value = 1.0
        value -= min(0.35, unknownSleepRatio * 0.6)
        value -= min(0.25, overlapDuration / max(session.timeInBed, 1) * 0.5)
        value -= min(0.20, gapDuration / max(session.timeInBed, 1) * 0.5)
        value -= min(0.20, Double(conflictCount) * 0.03)
        score = max(0, min(1, value))
    }

    var label: String {
        switch score {
        case 0.85...1: return "High confidence"
        case 0.65..<0.85: return "Good confidence"
        case 0.45..<0.65: return "Mixed confidence"
        default: return "Low confidence"
        }
    }
}
