import Foundation

/// Converts HealthKit stage samples into the app's one-primary-sleep-per-day model.
///
/// HealthKit can contain naps and an overnight sleep in the same noon-to-noon
/// bucket. Treating that whole bucket as one session makes the hours between the
/// nap and bedtime look like time in bed, so split distinct episodes first and
/// retain the episode with the most actual sleep.
nonisolated enum SleepSessionGrouper {
    private static let defaultEpisodeSplitGap: TimeInterval = 3 * 60 * 60

    static func primarySessions(
        from stages: [SleepStage],
        movementSamples: [MovementSample] = [],
        calendar: Calendar = .current,
        episodeSplitGap: TimeInterval = defaultEpisodeSplitGap
    ) -> [SleepSession] {
        var stagesByMorning: [Date: [SleepStage]] = [:]

        for stage in stages {
            let midpoint = Date(
                timeIntervalSince1970:
                    (stage.startDate.timeIntervalSince1970 + stage.endDate.timeIntervalSince1970) / 2
            )
            let morningDate: Date
            if calendar.component(.hour, from: midpoint) < 12 {
                morningDate = calendar.startOfDay(for: midpoint)
            } else {
                let nextDay = calendar.date(byAdding: .day, value: 1, to: midpoint) ?? midpoint
                morningDate = calendar.startOfDay(for: nextDay)
            }
            stagesByMorning[morningDate, default: []].append(stage)
        }

        return stagesByMorning.compactMap { morningDate, bucketStages in
            let candidates = episodes(from: bucketStages, splitGap: episodeSplitGap).map { episode in
                let start = episode.map(\.startDate).min() ?? morningDate
                let end = episode.map(\.endDate).max() ?? morningDate
                let movements = movementSamples.filter {
                    $0.startDate < end.addingTimeInterval(5 * 60)
                        && $0.endDate > start.addingTimeInterval(-2 * 60)
                }
                return SleepSession(
                    nightDate: morningDate,
                    stages: episode,
                    movementSamples: movements
                )
            }

            return candidates.max { lhs, rhs in
                if lhs.totalSleep != rhs.totalSleep {
                    return lhs.totalSleep < rhs.totalSleep
                }
                if lhs.timeInBed != rhs.timeInBed {
                    return lhs.timeInBed < rhs.timeInBed
                }
                return lhs.endTime < rhs.endTime
            }
        }
        .sorted { $0.nightDate > $1.nightDate }
    }

    private static func episodes(
        from stages: [SleepStage],
        splitGap: TimeInterval
    ) -> [[SleepStage]] {
        let sorted = stages.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            return lhs.endDate < rhs.endDate
        }
        guard let first = sorted.first else { return [] }

        var result: [[SleepStage]] = []
        var current = [first]
        var currentEnd = first.endDate

        for stage in sorted.dropFirst() {
            if stage.startDate.timeIntervalSince(currentEnd) >= splitGap {
                result.append(current)
                current = [stage]
                currentEnd = stage.endDate
            } else {
                current.append(stage)
                currentEnd = max(currentEnd, stage.endDate)
            }
        }
        result.append(current)
        return result
    }
}
