import Foundation

extension SleepWidgetSnapshot {
    /// Flattens a session into the value the widget reads. All the analysis
    /// stays here in the app; the extension only formats what this produces.
    init(session: SleepSession, generatedAt: Date = Date()) {
        let total = session.totalSleep
        func shareOfSleep(_ duration: TimeInterval) -> Double {
            total > 0 ? duration / total : 0
        }

        let durations: [(SleepWidgetStage, TimeInterval)] = [
            (.core, session.coreDuration),
            (.deep, session.deepDuration),
            (.rem, session.remDuration),
            (.unspecified, session.unspecifiedSleepDuration),
            (.awake, session.awakeDuration),
        ]

        self.init(
            nightDate: session.nightDate,
            totalSleep: total,
            timeInBed: session.timeInBed,
            efficiency: session.efficiency,
            sleepLatency: session.sleepLatency,
            // Zero-length stages are dropped so the views never have to guard
            // against empty rows or zero-width bar segments.
            slices: durations
                .filter { $0.1 > 0 }
                .map { SleepWidgetStageSlice(stage: $0.0, duration: $0.1, ratio: shareOfSleep($0.1)) },
            generatedAt: generatedAt
        )
    }
}
