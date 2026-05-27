import Foundation

struct MovementSample: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let stepCount: Double
    let distance: Double
    let standHourCount: Double
    let sourceName: String?

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
    let id = UUID()
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
}

enum AwakeEventDetector {
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

        return (awakeEvents + inferredStandEvents(for: session, excluding: evidenceWindows))
            .sorted { $0.startDate < $1.startDate }
    }

    static func movementEvidenceWindows(for session: SleepSession) -> [DateInterval] {
        movementEvidenceWindows(for: movementEligibleAwakeSegments(for: session))
    }

    static func standEvidenceWindow(for session: SleepSession) -> DateInterval? {
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

    private static func inferredStandEvents(
        for session: SleepSession,
        excluding existingWindows: [DateInterval]
    ) -> [AwakeEvent] {
        guard let sleepWindow = sleepWindow(for: session) else { return [] }

        return session.movementSamples
            .filter { $0.standHourCount > 0 }
            .compactMap { sample -> AwakeEvent? in
                let sampleWindow = DateInterval(start: sample.startDate, end: sample.endDate)
                guard sampleWindow.intersects(sleepWindow),
                      !existingWindows.contains(where: { $0.intersects(sampleWindow) }) else {
                    return nil
                }

                let eventStart = max(sample.startDate, sleepWindow.start)
                let availableDuration = min(sample.endDate, sleepWindow.end).timeIntervalSince(eventStart)
                guard availableDuration > 0 else { return nil }

                let eventDuration = min(10 * 60, max(60, availableDuration))
                let eventEnd = min(eventStart.addingTimeInterval(eventDuration), sleepWindow.end)
                return AwakeEvent(
                    startDate: eventStart,
                    endDate: eventEnd,
                    duration: eventEnd.timeIntervalSince(eventStart),
                    stepCount: sample.stepCount,
                    distance: sample.distance,
                    standHourCount: sample.standHourCount,
                    classification: .likelyOutOfBed,
                    confidence: confidence(
                        for: .likelyOutOfBed,
                        stepCount: sample.stepCount,
                        distance: sample.distance,
                        standHourCount: sample.standHourCount
                    )
                )
            }
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
