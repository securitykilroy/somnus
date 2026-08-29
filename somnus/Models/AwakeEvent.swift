import Foundation

struct MovementSample: Identifiable {
    let startDate: Date
    let endDate: Date
    let stepCount: Double
    let distance: Double
    let standHourCount: Double
    let sourceName: String?

    var id: String {
        [
            startDate.timeIntervalSinceReferenceDate.description,
            endDate.timeIntervalSinceReferenceDate.description,
            stepCount.description,
            distance.description,
            standHourCount.description,
            sourceName ?? "",
        ].joined(separator: "|")
    }

    init(
        startDate: Date,
        endDate: Date,
        stepCount: Double = 0,
        distance: Double = 0,
        standHourCount: Double = 0,
        sourceName: String? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.stepCount = stepCount
        self.distance = distance
        self.standHourCount = standHourCount
        self.sourceName = sourceName
    }
}

enum AwakeEventClassification: String {
    case restlessInBed = "Restless in Bed"
    case likelyOutOfBed = "Likely Out of Bed"
    case unknown = "Unknown"
}

struct AwakeEvent: Identifiable {
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let stepCount: Double
    let distance: Double
    let standHourCount: Double
    let classification: AwakeEventClassification
    let confidence: Double

    var isMovementConfirmed: Bool {
        classification == .likelyOutOfBed
    }

    var id: String {
        [
            startDate.timeIntervalSinceReferenceDate.description,
            endDate.timeIntervalSinceReferenceDate.description,
            classification.rawValue,
            stepCount.description,
            distance.description,
            standHourCount.description,
        ].joined(separator: "|")
    }
}

enum AwakeEventDetector {
    private static let outOfBedMergeGap: TimeInterval = 20 * 60

    static func events(for session: SleepSession) -> [AwakeEvent] {
        let awakeSegments = movementEligibleAwakeSegments(for: session)
        let evidenceWindows = movementEvidenceWindows(for: awakeSegments)

        let awakeEvents = zip(awakeSegments, evidenceWindows).map { segment, window in
            let evidence = movementEvidence(
                in: window,
                movementSamples: session.movementSamples
            )
            let classification = classify(
                stepCount: evidence.steps,
                distance: evidence.distance,
                standHourCount: evidence.standHours
            )
            return AwakeEvent(
                startDate: segment.startDate,
                endDate: segment.endDate,
                duration: segment.duration,
                stepCount: evidence.steps,
                distance: evidence.distance,
                standHourCount: evidence.standHours,
                classification: classification,
                confidence: confidence(
                    for: classification,
                    stepCount: evidence.steps,
                    distance: evidence.distance,
                    standHourCount: evidence.standHours
                )
            )
        }

        let events = (awakeEvents + inferredMovementEvents(for: session, excluding: evidenceWindows))
            .sorted { $0.startDate < $1.startDate }

        return coalescedOutOfBedEvents(events)
    }

    static func movementEvidenceWindows(for session: SleepSession) -> [DateInterval] {
        movementEvidenceWindows(for: movementEligibleAwakeSegments(for: session))
    }

    static func standEvidenceWindow(for session: SleepSession) -> DateInterval? {
        sleepWindow(for: session)
    }

    static func sleepMovementEvidenceWindow(for session: SleepSession) -> DateInterval? {
        sleepWindow(for: session)
    }

    private static func sleepWindow(for session: SleepSession) -> DateInterval? {
        guard let firstSleep = session.normalizedTimeline.firstSleepStart,
              let lastSleep = session.normalizedTimeline.lastSleepEnd,
              firstSleep < lastSleep else {
            return nil
        }
        return DateInterval(start: firstSleep, end: lastSleep)
    }

    private static func movementEligibleAwakeSegments(for session: SleepSession) -> [SleepTimelineSegment] {
        guard let sleepWindow = sleepWindow(for: session) else {
            return []
        }

        return session.normalizedTimeline.segments
            .filter { $0.type == .awake && $0.startDate >= sleepWindow.start && $0.endDate <= sleepWindow.end }
    }

    private static func movementEvidenceWindows(for segments: [SleepTimelineSegment]) -> [DateInterval] {
        segments.map { segment in
            DateInterval(
                start: segment.startDate.addingTimeInterval(-2 * 60),
                end: segment.endDate.addingTimeInterval(5 * 60)
            )
        }
    }

    private static func movementEvidence(
        in window: DateInterval,
        movementSamples: [MovementSample]
    ) -> (steps: Double, distance: Double, standHours: Double) {
        let overlapping = movementSamples.filter { $0.startDate < window.end && $0.endDate > window.start }
        return overlapping.reduce((steps: 0, distance: 0, standHours: 0)) { partial, sample in
            (
                partial.steps + sample.stepCount,
                partial.distance + sample.distance,
                partial.standHours + sample.standHourCount
            )
        }
    }

    private static func inferredMovementEvents(
        for session: SleepSession,
        excluding existingWindows: [DateInterval]
    ) -> [AwakeEvent] {
        guard let sleepWindow = sleepWindow(for: session) else { return [] }

        let movementClusters = clusteredMovementSamples(
            session.movementSamples.filter { sample in
                let window = sampleWindow(sample)
                return (sample.stepCount > 0 || sample.distance > 0)
                    && window.intersects(sleepWindow)
                    && !existingWindows.contains(where: { $0.intersects(window) })
            }
        )

        var events = movementClusters.compactMap { cluster -> AwakeEvent? in
            inferredEvent(
                from: cluster,
                sleepWindow: sleepWindow,
                movementSamples: session.movementSamples
            )
        }

        let eventWindows = events.map { DateInterval(start: $0.startDate, end: $0.endDate) }
        let standEvents = session.movementSamples
            .filter { $0.standHourCount > 0 }
            .compactMap { sample -> AwakeEvent? in
                let sampleWindow = DateInterval(start: sample.startDate, end: sample.endDate)
                guard sampleWindow.intersects(sleepWindow),
                      !existingWindows.contains(where: { $0.intersects(sampleWindow) }),
                      !eventWindows.contains(where: { $0.intersects(sampleWindow) }) else {
                    return nil
                }

                return inferredEvent(
                    from: [sample],
                    sleepWindow: sleepWindow,
                    movementSamples: session.movementSamples
                )
            }

        events.append(contentsOf: standEvents)
        return events
    }

    private static func clusteredMovementSamples(_ samples: [MovementSample]) -> [[MovementSample]] {
        let sorted = samples.sorted { $0.startDate < $1.startDate }
        var clusters: [[MovementSample]] = []

        for sample in sorted {
            guard var current = clusters.popLast() else {
                clusters.append([sample])
                continue
            }

            let currentEnd = current.map(\.endDate).max() ?? sample.endDate
            if sample.startDate.timeIntervalSince(currentEnd) <= 5 * 60 {
                current.append(sample)
                clusters.append(current)
            } else {
                clusters.append(current)
                clusters.append([sample])
            }
        }

        return clusters
    }

    private static func coalescedOutOfBedEvents(_ events: [AwakeEvent]) -> [AwakeEvent] {
        var result: [AwakeEvent] = []

        for event in events {
            guard event.classification == .likelyOutOfBed,
                  let last = result.last,
                  last.classification == .likelyOutOfBed,
                  event.startDate.timeIntervalSince(last.endDate) <= outOfBedMergeGap else {
                result.append(event)
                continue
            }

            result[result.count - 1] = mergedOutOfBedEvent(last, event)
        }

        return result
    }

    private static func mergedOutOfBedEvent(_ first: AwakeEvent, _ second: AwakeEvent) -> AwakeEvent {
        let startDate = min(first.startDate, second.startDate)
        let endDate = max(first.endDate, second.endDate)
        let stepCount = max(first.stepCount, second.stepCount)
        let distance = max(first.distance, second.distance)
        let standHourCount = max(first.standHourCount, second.standHourCount)
        let classification = classify(
            stepCount: stepCount,
            distance: distance,
            standHourCount: standHourCount
        )

        return AwakeEvent(
            startDate: startDate,
            endDate: endDate,
            duration: endDate.timeIntervalSince(startDate),
            stepCount: stepCount,
            distance: distance,
            standHourCount: standHourCount,
            classification: classification,
            confidence: max(
                first.confidence,
                confidence(
                    for: classification,
                    stepCount: stepCount,
                    distance: distance,
                    standHourCount: standHourCount
                )
            )
        )
    }

    private static func inferredEvent(
        from samples: [MovementSample],
        sleepWindow: DateInterval,
        movementSamples: [MovementSample]
    ) -> AwakeEvent? {
        guard let sampleStart = samples.map(\.startDate).min(),
              let sampleEnd = samples.map(\.endDate).max() else {
            return nil
        }

        let eventStart = max(sampleStart, sleepWindow.start)
        let availableDuration = min(sampleEnd, sleepWindow.end).timeIntervalSince(eventStart)
        guard availableDuration > 0 else { return nil }

        let eventDuration = min(10 * 60, max(60, availableDuration))
        let eventEnd = min(eventStart.addingTimeInterval(eventDuration), sleepWindow.end)
        let evidenceWindow = DateInterval(
            start: eventStart.addingTimeInterval(-2 * 60),
            end: eventEnd.addingTimeInterval(5 * 60)
        )
        let evidence = movementEvidence(in: evidenceWindow, movementSamples: movementSamples)
        let classification = classify(
            stepCount: evidence.steps,
            distance: evidence.distance,
            standHourCount: evidence.standHours
        )

        guard classification != .restlessInBed else { return nil }

        return AwakeEvent(
            startDate: eventStart,
            endDate: eventEnd,
            duration: eventEnd.timeIntervalSince(eventStart),
            stepCount: evidence.steps,
            distance: evidence.distance,
            standHourCount: evidence.standHours,
            classification: classification,
            confidence: confidence(
                for: classification,
                stepCount: evidence.steps,
                distance: evidence.distance,
                standHourCount: evidence.standHours
            )
        )
    }

    private static func sampleWindow(_ sample: MovementSample) -> DateInterval {
        DateInterval(start: sample.startDate, end: sample.endDate)
    }

    private static func classify(
        stepCount: Double,
        distance: Double,
        standHourCount: Double
    ) -> AwakeEventClassification {
        if stepCount >= 8 || distance >= 5 || standHourCount > 0 {
            return .likelyOutOfBed
        }
        if stepCount > 0 || distance > 0 {
            return .unknown
        }
        return .restlessInBed
    }

    private static func confidence(
        for classification: AwakeEventClassification,
        stepCount: Double,
        distance: Double,
        standHourCount: Double
    ) -> Double {
        switch classification {
        case .likelyOutOfBed:
            return min(1, 0.65 + min(stepCount / 40, 0.20) + min(distance / 40, 0.10) + min(standHourCount * 0.20, 0.20))
        case .unknown:
            return 0.45
        case .restlessInBed:
            return 0.70
        }
    }
}
