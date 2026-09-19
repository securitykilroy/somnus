import Foundation

nonisolated struct SleepTimelineSegment: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let type: SleepStageType
    let sourceNames: [String]
    let contributingStageIDs: [UUID]

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }
}

nonisolated struct NormalizedSleepTimeline {
    let rawStages: [SleepStage]
    let segments: [SleepTimelineSegment]
    let totalOverlap: TimeInterval
    let totalGap: TimeInterval
    let conflictingSegmentCount: Int

    /// Summed once at construction rather than on every read: `duration(for:)`
    /// used to filter the whole segment list, and it is read per stage type per
    /// night inside chart loops.
    private let durationsByType: [SleepStageType: TimeInterval]
    let sleepDuration: TimeInterval
    let firstSleepStart: Date?
    let lastSleepEnd: Date?

    init(
        rawStages: [SleepStage],
        segments: [SleepTimelineSegment],
        totalOverlap: TimeInterval,
        totalGap: TimeInterval,
        conflictingSegmentCount: Int
    ) {
        self.rawStages = rawStages
        self.segments = segments
        self.totalOverlap = totalOverlap
        self.totalGap = totalGap
        self.conflictingSegmentCount = conflictingSegmentCount

        var durations: [SleepStageType: TimeInterval] = [:]
        var sleep: TimeInterval = 0
        var firstSleep: Date?
        var lastSleep: Date?
        for segment in segments {
            durations[segment.type, default: 0] += segment.duration
            if segment.type.isSleep {
                sleep += segment.duration
                if firstSleep == nil { firstSleep = segment.startDate }
                lastSleep = segment.endDate
            }
        }
        self.durationsByType = durations
        self.sleepDuration = sleep
        self.firstSleepStart = firstSleep
        self.lastSleepEnd = lastSleep
    }

    func duration(for type: SleepStageType) -> TimeInterval {
        durationsByType[type] ?? 0
    }
}

nonisolated enum SleepTimelineNormalizer {
    static func normalize(_ stages: [SleepStage]) -> NormalizedSleepTimeline {
        let validStages = stages
            .filter { $0.endDate > $0.startDate }
            .sorted { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.type.analysisPriority > rhs.type.analysisPriority
                }
                return lhs.startDate < rhs.startDate
            }

        guard validStages.count > 1 else {
            let segments = validStages.map { stage in
                SleepTimelineSegment(
                    startDate: stage.startDate,
                    endDate: stage.endDate,
                    type: stage.type,
                    sourceNames: stage.sourceName.map { [$0] } ?? [],
                    contributingStageIDs: [stage.id]
                )
            }
            return NormalizedSleepTimeline(
                rawStages: validStages,
                segments: segments,
                totalOverlap: 0,
                totalGap: 0,
                conflictingSegmentCount: 0
            )
        }

        let boundaries = Array(Set(validStages.flatMap { [$0.startDate, $0.endDate] })).sorted()
        var segments: [SleepTimelineSegment] = []
        var totalOverlap: TimeInterval = 0
        var totalGap: TimeInterval = 0
        var conflictingSegmentCount = 0

        // Swept rather than re-filtered. The old loop ran
        // `validStages.filter` once per boundary, which is O(stages²) per
        // night and, across a three-year history, the bulk of a load. Because
        // `validStages` is sorted by start date, the stages overlapping each
        // boundary interval can be maintained incrementally.
        var active: [SleepStage] = []
        var nextStageIndex = 0

        for index in 0..<(boundaries.count - 1) {
            let start = boundaries[index]
            let end = boundaries[index + 1]
            guard end > start else { continue }

            while nextStageIndex < validStages.count, validStages[nextStageIndex].startDate < end {
                active.append(validStages[nextStageIndex])
                nextStageIndex += 1
            }
            active.removeAll { $0.endDate <= start }

            guard !active.isEmpty else {
                totalGap += end.timeIntervalSince(start)
                continue
            }

            if active.count > 1 {
                totalOverlap += end.timeIntervalSince(start)
            }
            if Set(active.map(\.type)).count > 1 {
                conflictingSegmentCount += 1
            }

            let winner = active.max { lhs, rhs in
                if lhs.type.analysisPriority == rhs.type.analysisPriority {
                    return lhs.duration < rhs.duration
                }
                return lhs.type.analysisPriority < rhs.type.analysisPriority
            }!

            segments.append(
                SleepTimelineSegment(
                    startDate: start,
                    endDate: end,
                    type: winner.type,
                    sourceNames: Array(Set(active.compactMap(\.sourceName))).sorted(),
                    contributingStageIDs: active.map(\.id)
                )
            )
        }

        return NormalizedSleepTimeline(
            rawStages: validStages,
            segments: segments,
            totalOverlap: totalOverlap,
            totalGap: totalGap,
            conflictingSegmentCount: conflictingSegmentCount
        )
    }

}
