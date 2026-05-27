import Foundation

struct SleepTimelineSegment: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let type: SleepStageType
    let sourceNames: [String]
    let contributingStageIDs: [UUID]

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }
}

struct NormalizedSleepTimeline {
    let rawStages: [SleepStage]
    let segments: [SleepTimelineSegment]
    let totalOverlap: TimeInterval
    let totalGap: TimeInterval
    let conflictingSegmentCount: Int

    func duration(for type: SleepStageType) -> TimeInterval {
        segments.filter { $0.type == type }.reduce(0) { $0 + $1.duration }
    }

    var sleepDuration: TimeInterval {
        segments.filter(\.type.isSleep).reduce(0) { $0 + $1.duration }
    }

    var firstSleepStart: Date? {
        segments.first(where: { $0.type.isSleep })?.startDate
    }

    var lastSleepEnd: Date? {
        segments.last(where: { $0.type.isSleep })?.endDate
    }
}

enum SleepTimelineNormalizer {
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

        for index in 0..<(boundaries.count - 1) {
            let start = boundaries[index]
            let end = boundaries[index + 1]
            guard end > start else { continue }

            let active = validStages.filter { $0.startDate < end && $0.endDate > start }
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
