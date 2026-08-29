import Foundation

struct SleepSession: Identifiable {
    let id: UUID
    let nightDate: Date
    let stages: [SleepStage]
    let movementSamples: [MovementSample]
    let normalizedTimeline: NormalizedSleepTimeline
    let startTime: Date
    let endTime: Date

    init(nightDate: Date, stages: [SleepStage], movementSamples: [MovementSample] = []) {
        self.id = UUID()
        self.nightDate = nightDate
        self.stages = stages
        self.movementSamples = movementSamples
        self.normalizedTimeline = SleepTimelineNormalizer.normalize(stages)
        self.startTime = stages.min(by: { $0.startDate < $1.startDate })?.startDate ?? nightDate
        self.endTime = stages.max(by: { $0.endDate < $1.endDate })?.endDate ?? nightDate
    }

    /// Copies a session with new movement samples, reusing the already-computed timeline
    /// to avoid re-running the O(n²) normalizer when only movement evidence changes.
    init(copying original: SleepSession, movementSamples: [MovementSample]) {
        self.id = original.id
        self.nightDate = original.nightDate
        self.stages = original.stages
        self.movementSamples = movementSamples
        self.normalizedTimeline = original.normalizedTimeline
        self.startTime = original.startTime
        self.endTime = original.endTime
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

    var timeInBed: TimeInterval {
        guard let start = stages.min(by: { $0.startDate < $1.startDate })?.startDate,
              let end = stages.max(by: { $0.endDate < $1.endDate })?.endDate else { return 0 }
        return end.timeIntervalSince(start)
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

    var wakeAfterSleepOnset: TimeInterval {
        guard let firstSleep = normalizedTimeline.firstSleepStart,
              let lastSleep = normalizedTimeline.lastSleepEnd else { return 0 }
        return normalizedTimeline.segments
            .filter { $0.type == .awake && $0.startDate >= firstSleep && $0.endDate <= lastSleep }
            .reduce(0) { $0 + $1.duration }
    }

    var awakeningCount: Int {
        guard let firstSleep = normalizedTimeline.firstSleepStart,
              let lastSleep = normalizedTimeline.lastSleepEnd else { return 0 }
        return normalizedTimeline.segments
            .filter { $0.type == .awake && $0.startDate >= firstSleep && $0.endDate <= lastSleep }
            .count
    }

    var longestSleepBlock: TimeInterval {
        var longest: TimeInterval = 0
        var current: TimeInterval = 0
        for segment in normalizedTimeline.segments {
            if segment.type.isSleep {
                current += segment.duration
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
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

    var awakeEvents: [AwakeEvent] {
        AwakeEventDetector.events(for: self)
    }

    var movementConfirmedAwakeningCount: Int {
        awakeEvents.filter(\.isMovementConfirmed).count
    }

    var likelyOutOfBedDuration: TimeInterval {
        awakeEvents
            .filter(\.isMovementConfirmed)
            .reduce(0) { $0 + $1.duration }
    }

    var transitionCount: Int {
        let stages = normalizedTimeline.segments
        guard stages.count > 1 else { return 0 }
        var count = 0
        for i in 1..<stages.count {
            if stages[i].type != stages[i - 1].type { count += 1 }
        }
        return count
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

struct MorningWakeAnalysis {
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

struct SleepDataQuality {
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
