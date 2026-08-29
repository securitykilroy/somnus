import Foundation

struct CSVExportFile {
    let filename: String
    let content: String

    func writeTemporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SomnusExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename)
        try content.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }
}

enum CSVExporter {
    static func trendsFile(
        sessions: [SleepSession],
        dailyCalories: [DailyMetricSample],
        dailyRestingHR: [DailyMetricSample],
        dailyHRV: [DailyMetricSample],
        sleepHeartRates: [Date: Double],
        meals: [MealEvent] = [],
        calendar: Calendar = .current
    ) -> CSVExportFile {
        let sortedSessions = sessions.sorted { $0.nightDate < $1.nightDate }
        let caloriesByDay = metricDictionary(dailyCalories, calendar: calendar)
        let restingHRByDay = metricDictionary(dailyRestingHR, calendar: calendar)
        let hrvByDay = metricDictionary(dailyHRV, calendar: calendar)
        let sleepHRByDay = Dictionary(
            sleepHeartRates.map { (calendar.startOfDay(for: $0.key), $0.value) },
            uniquingKeysWith: { $1 }
        )

        let header = [
            "night_date",
            "bedtime",
            "wake_time",
            "total_sleep_minutes",
            "efficiency",
            "waso_minutes",
            "awakenings",
            "out_of_bed_count",
            "out_of_bed_minutes",
            "fragmentation_index",
            "deep_minutes",
            "rem_minutes",
            "core_minutes",
            "active_calories",
            "resting_hr",
            "hrv",
            "sleep_hr",
            "meal_count",
            "first_meal_time",
            "last_meal_time",
            "hours_last_meal_to_sleep",
            "meals",
        ]
        let rows = sortedSessions.map { session in
            let activityDay = calendar.date(byAdding: .day, value: -1, to: session.nightDate)
                .map { calendar.startOfDay(for: $0) }
            let nightDate = calendar.startOfDay(for: session.nightDate)
            let nightMeals = MealSleepAnalyzer.meals(
                precedingSleepIn: session,
                from: meals,
                calendar: calendar
            )
            // Split from the sleep columns below: as one literal the row grew
            // past what the type checker will infer in reasonable time.
            let mealColumns = mealColumns(for: nightMeals, session: session)
            let sleepColumns: [String] = [
                dateOnly(session.nightDate, calendar: calendar),
                timestamp(session.startTime),
                timestamp(session.endTime),
                number(session.totalSleep / 60),
                number(session.efficiency),
                number(session.wakeAfterSleepOnset / 60),
                "\(session.awakeningCount)",
                "\(session.movementConfirmedAwakeningCount)",
                number(session.likelyOutOfBedDuration / 60),
                number(session.fragmentationIndex),
                number(session.deepDuration / 60),
                number(session.remDuration / 60),
                number(session.coreDuration / 60),
                activityDay.flatMap { caloriesByDay[$0] }.map { number($0) } ?? "",
                restingHRByDay[nightDate].map { number($0) } ?? "",
                hrvByDay[nightDate].map { number($0) } ?? "",
                sleepHRByDay[nightDate].map { number($0) } ?? "",
            ]
            return sleepColumns + mealColumns
        }

        let filename = trendsFilename(for: sortedSessions, calendar: calendar)
        return CSVExportFile(filename: filename, content: csv(rows: [header] + rows))
    }

    static func dailyFile(
        for session: SleepSession,
        meals: [MealEvent] = [],
        calendar: Calendar = .current
    ) -> CSVExportFile {
        let header = [
            "record_type",
            "night_date",
            "start",
            "end",
            "duration_minutes",
            "metric",
            "value",
            "unit",
            "stage_type",
            "classification",
            "confidence",
            "steps",
            "distance_meters",
            "stand_hours",
            "source",
            "note",
        ]
        let nightDate = dateOnly(session.nightDate, calendar: calendar)
        var rows: [[String]] = [header]

        rows.append(contentsOf: summaryRows(for: session, nightDate: nightDate))

        rows.append(contentsOf: session.normalizedTimeline.segments.map { segment in
            [
                "stage",
                nightDate,
                timestamp(segment.startDate),
                timestamp(segment.endDate),
                number(segment.duration / 60),
                "",
                "",
                "",
                segment.type.rawValue,
                "",
                "",
                "",
                "",
                "",
                segment.sourceNames.joined(separator: ";"),
                "",
            ]
        })

        rows.append(contentsOf: session.awakeEvents.map { event in
            [
                "awake_event",
                nightDate,
                timestamp(event.startDate),
                timestamp(event.endDate),
                number(event.duration / 60),
                "",
                "",
                "",
                "",
                event.classification.rawValue,
                number(event.confidence),
                number(event.stepCount),
                number(event.distance),
                number(event.standHourCount),
                "",
                "",
            ]
        })

        rows.append(contentsOf: session.movementSamples.map { sample in
            [
                "movement",
                nightDate,
                timestamp(sample.startDate),
                timestamp(sample.endDate),
                number(sample.endDate.timeIntervalSince(sample.startDate) / 60),
                "",
                "",
                "",
                "",
                "",
                "",
                number(sample.stepCount),
                number(sample.distance),
                number(sample.standHourCount),
                sample.sourceName ?? "",
                "",
            ]
        })

        // Placed last so the meal rows read as a block: everything eaten from
        // the previous morning up to sleep onset, in order.
        rows.append(contentsOf: MealSleepAnalyzer.meals(
            precedingSleepIn: session,
            from: meals,
            calendar: calendar
        ).map { meal in
            [
                "meal",
                nightDate,
                timestamp(meal.timestamp),
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                meal.note,
            ]
        })

        return CSVExportFile(
            filename: "somnus-daily-\(nightDate).csv",
            content: csv(rows: rows)
        )
    }

    private static func summaryRows(for session: SleepSession, nightDate: String) -> [[String]] {
        [
            summaryRow(nightDate: nightDate, duration: session.totalSleep, metric: "total_sleep", value: session.totalSleep / 60, unit: "minutes"),
            summaryRow(nightDate: nightDate, duration: session.timeInBed, metric: "time_in_bed", value: session.timeInBed / 60, unit: "minutes"),
            summaryRow(nightDate: nightDate, duration: session.wakeAfterSleepOnset, metric: "waso", value: session.wakeAfterSleepOnset / 60, unit: "minutes"),
            summaryRow(nightDate: nightDate, duration: session.likelyOutOfBedDuration, metric: "out_of_bed", value: session.likelyOutOfBedDuration / 60, unit: "minutes"),
            summaryRow(nightDate: nightDate, duration: nil, metric: "efficiency", value: session.efficiency, unit: "ratio"),
            summaryRow(nightDate: nightDate, duration: nil, metric: "awakenings", value: Double(session.awakeningCount), unit: "count"),
            summaryRow(nightDate: nightDate, duration: nil, metric: "out_of_bed_count", value: Double(session.movementConfirmedAwakeningCount), unit: "count"),
            summaryRow(nightDate: nightDate, duration: nil, metric: "fragmentation_index", value: session.fragmentationIndex, unit: "ratio"),
            summaryRow(nightDate: nightDate, duration: session.coreDuration, metric: "core_sleep", value: session.coreDuration / 60, unit: "minutes"),
            summaryRow(nightDate: nightDate, duration: session.deepDuration, metric: "deep_sleep", value: session.deepDuration / 60, unit: "minutes"),
            summaryRow(nightDate: nightDate, duration: session.remDuration, metric: "rem_sleep", value: session.remDuration / 60, unit: "minutes"),
        ]
    }

    private static func summaryRow(
        nightDate: String,
        duration: TimeInterval?,
        metric: String,
        value: Double,
        unit: String
    ) -> [String] {
        [
            "summary",
            nightDate,
            "",
            "",
            duration.map { number($0 / 60) } ?? "",
            metric,
            number(value),
            unit,
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
        ]
    }

    private static func trendsFilename(for sessions: [SleepSession], calendar: Calendar) -> String {
        guard let first = sessions.first?.nightDate,
              let last = sessions.last?.nightDate else {
            return "somnus-trends.csv"
        }
        return "somnus-trends-\(dateOnly(first, calendar: calendar))-to-\(dateOnly(last, calendar: calendar)).csv"
    }

    private static func mealColumns(for meals: [MealEvent], session: SleepSession) -> [String] {
        let onset = session.normalizedTimeline.firstSleepStart ?? session.startTime
        let last = meals.last
        return [
            "\(meals.count)",
            meals.first.map { timestamp($0.timestamp) } ?? "",
            last.map { timestamp($0.timestamp) } ?? "",
            last.map { number(onset.timeIntervalSince($0.timestamp) / 3600) } ?? "",
            mealList(meals),
        ]
    }

    /// Renders a night's meals into one cell as
    /// `<iso timestamp>|<what was eaten>` entries joined by `; `.
    ///
    /// Kept in the wide per-night file on purpose: the point of this export is
    /// to hand a tool one table where each row already pairs what was eaten
    /// with how that night went, rather than two files that have to be joined.
    /// `;`, `|` and newlines are neutralised so the sub-format stays parseable
    /// and stays on one visual line. Commas and quotes are left alone — the
    /// surrounding CSV quoting in `escape` handles those, and mangling them
    /// would corrupt the note for no gain.
    private static func mealList(_ meals: [MealEvent]) -> String {
        meals
            .map { meal in
                let note = meal.note
                    .replacingOccurrences(of: ";", with: ",")
                    .replacingOccurrences(of: "|", with: "/")
                    .replacingOccurrences(of: "\n", with: " ")
                return "\(timestamp(meal.timestamp))|\(note)"
            }
            .joined(separator: "; ")
    }

    private static func metricDictionary(
        _ samples: [DailyMetricSample],
        calendar: Calendar
    ) -> [Date: Double] {
        Dictionary(
            samples.map { (calendar.startOfDay(for: $0.date), $0.value) },
            uniquingKeysWith: { $1 }
        )
    }

    private static func csv(rows: [[String]]) -> String {
        rows
            .map { row in row.map { escape($0) }.joined(separator: ",") }
            .joined(separator: "\n") + "\n"
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func timestamp(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static func dateOnly(_ date: Date, calendar: Calendar) -> String {
        var calendar = calendar
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func number(_ value: Double) -> String {
        if value.isNaN || value.isInfinite { return "" }
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.3f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
