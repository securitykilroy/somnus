import Foundation
import Testing
@testable import somnus

struct MealLogStoreTests {
    private func temporaryDirectory() -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func temporaryStore() -> MealLogStore {
        MealLogStore(directory: temporaryDirectory())
    }

    /// Writes the log file directly, which is the only way to produce an entry
    /// whose `createdAt` is in the past — `append` always stamps it with now.
    private func seededStore(with events: [MealEvent]) -> MealLogStore {
        let directory = temporaryDirectory()
        let data = try! JSONEncoder().encode(events)
        try! data.write(to: directory.appendingPathComponent("meal-log.json"))
        return MealLogStore(directory: directory)
    }

    @Test func appendedEntriesSurviveARoundTrip() {
        let store = temporaryStore()
        let when = Date(timeIntervalSince1970: 1_800_000_000)

        let event = store.append(note: "Pasta", at: when)

        #expect(event != nil)
        let read = store.read()
        #expect(read.count == 1)
        #expect(read.first?.note == "Pasta")
        #expect(read.first?.timestamp == when)
    }

    @Test func entriesComeBackNewestFirst() {
        let store = temporaryStore()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        store.append(note: "Breakfast", at: base)
        store.append(note: "Dinner", at: base.addingTimeInterval(10 * 3600))
        store.append(note: "Lunch", at: base.addingTimeInterval(5 * 3600))

        #expect(store.read().map(\.note) == ["Dinner", "Lunch", "Breakfast"])
    }

    @Test func aNoteLessEntryStillRecordsTheTime() {
        let store = temporaryStore()

        let event = store.append(at: Date())

        #expect(event?.hasNote == false)
        #expect(event?.displayLabel == "Ate")
    }

    @Test func updatingTheTimeLeavesTheNoteAlone() {
        let store = temporaryStore()
        let event = store.append(note: "Steak", at: Date())!
        let corrected = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(store.update(id: event.id, timestamp: corrected))

        let read = store.read().first
        #expect(read?.note == "Steak")
        #expect(read?.timestamp == corrected)
    }

    @Test func updatingAnUnknownEntryReportsFailure() {
        let store = temporaryStore()
        store.append(note: "Steak", at: Date())

        #expect(!store.update(id: UUID(), note: "Fish"))
    }

    @Test func deletingRemovesOnlyTheNamedEntry() {
        let store = temporaryStore()
        let keep = store.append(note: "Lunch", at: Date())!
        let drop = store.append(note: "Snack", at: Date())!

        #expect(store.delete(id: drop.id))
        #expect(store.read().map(\.id) == [keep.id])
    }

    @Test func undoRemovesTheEntryJustCreated() {
        let store = temporaryStore()
        store.append(note: "Lunch", at: Date().addingTimeInterval(-4 * 3600))
        let mistake = store.append(at: Date())!

        #expect(store.removeMostRecent()?.id == mistake.id)
        #expect(store.read().map(\.note) == ["Lunch"])
    }

    /// Undo is for a mis-tap seconds old; it must not quietly prune history
    /// when nothing was logged recently.
    @Test func undoIgnoresEntriesLoggedLongAgo() {
        let yesterday = Date().addingTimeInterval(-26 * 3600)
        let store = seededStore(with: [
            MealEvent(timestamp: yesterday, note: "Yesterday", createdAt: yesterday, updatedAt: yesterday)
        ])

        #expect(store.removeMostRecent(within: 15 * 60) == nil)
        #expect(store.read().count == 1)
    }

    /// Backdating is a normal way to log — a tap that says "30m ago" is still
    /// something you just created, so undo has to reach it.
    @Test func undoReachesAnEntryThatWasBackdated() {
        let store = temporaryStore()
        let backdated = store.append(at: Date().addingTimeInterval(-60 * 60))!

        #expect(store.removeMostRecent()?.id == backdated.id)
        #expect(store.read().isEmpty)
    }

    @Test func writingWithoutAContainerFailsWithoutCrashing() {
        let store = MealLogStore(directory: nil)

        #expect(store.append(note: "Pasta") == nil)
        #expect(store.read().isEmpty)
    }

    @Test func todaysEntriesExcludeOtherDays() {
        let store = temporaryStore()
        let now = Date()
        store.append(note: "Today", at: now)
        store.append(note: "Yesterday", at: now.addingTimeInterval(-36 * 3600))

        #expect(store.events(on: now).map(\.note) == ["Today"])
    }
}

struct MealSleepAnalyzerTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func session(bedtime: Date, hours: Double = 7) -> SleepSession {
        SleepSession(
            nightDate: calendar.startOfDay(for: bedtime.addingTimeInterval(10 * 3600)),
            stages: [
                SleepStage(startDate: bedtime, endDate: bedtime.addingTimeInterval(15 * 60), type: .awake),
                SleepStage(
                    startDate: bedtime.addingTimeInterval(15 * 60),
                    endDate: bedtime.addingTimeInterval(hours * 3600),
                    type: .core
                ),
            ]
        )
    }

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = .current
        return formatter.date(from: string)!
    }

    @Test func pairsANightWithTheLastMealBeforeSleepOnset() {
        let bedtime = date("2026-05-01 22:30")
        let meals = [
            MealEvent(timestamp: date("2026-05-01 12:30"), note: "Lunch"),
            MealEvent(timestamp: date("2026-05-01 18:45"), note: "Dinner"),
        ]

        let records = MealSleepAnalyzer.records(sessions: [session(bedtime: bedtime)], meals: meals)

        #expect(records.count == 1)
        #expect(records.first?.mealLabel == "Dinner")
        // Onset is 15 minutes after bedtime, so 22:45 minus 18:45.
        #expect(records.first?.gapHours == 4)
    }

    @Test func ignoresMealsAfterSleepOnset() {
        let bedtime = date("2026-05-01 22:30")
        let meals = [MealEvent(timestamp: date("2026-05-02 08:00"), note: "Breakfast")]

        #expect(MealSleepAnalyzer.records(sessions: [session(bedtime: bedtime)], meals: meals).isEmpty)
    }

    /// A stale entry from a day nobody logged would otherwise show up as a
    /// 30-hour gap and drag the regression with it.
    @Test func ignoresMealsBeyondTheMaximumGap() {
        let bedtime = date("2026-05-02 22:30")
        let meals = [MealEvent(timestamp: date("2026-05-01 18:00"), note: "Two nights ago")]

        #expect(MealSleepAnalyzer.records(sessions: [session(bedtime: bedtime)], meals: meals).isEmpty)
    }

    @Test func nightsWithoutAnyLoggedMealAreDropped() {
        #expect(MealSleepAnalyzer.records(sessions: [session(bedtime: date("2026-05-01 22:30"))], meals: []).isEmpty)
    }

    @Test func summarySplitsNightsAtTheLateThreshold() {
        let lateNight = date("2026-05-01 22:30")
        let earlyNight = date("2026-05-02 22:30")
        let sessions = [session(bedtime: lateNight), session(bedtime: earlyNight)]
        let meals = [
            MealEvent(timestamp: date("2026-05-01 21:30"), note: "Late snack"),
            MealEvent(timestamp: date("2026-05-02 17:30"), note: "Early dinner"),
        ]

        let summary = MealSleepAnalyzer.summary(
            records: MealSleepAnalyzer.records(sessions: sessions, meals: meals)
        )

        #expect(summary.lateNights.map(\.mealLabel) == ["Late snack"])
        #expect(summary.earlyNights.map(\.mealLabel) == ["Early dinner"])
        #expect(!summary.hasComparison)
    }
}

struct MealCSVExportTests {
    // Pinned to UTC, matching the rest of the export tests: `dateOnly` renders
    // in UTC, so a local-zone calendar would put `startOfDay` on the wrong day.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = TimeZone(secondsFromGMT: 0)!
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string)!
    }

    /// Bed at 22:00 on the 2nd, asleep 22:15, up at 06:00 on the 3rd, so the
    /// night is dated the 3rd and its eating day is the 2nd.
    private func session() -> SleepSession {
        let bedtime = date("2026-05-02 22:00")
        return SleepSession(
            nightDate: calendar.startOfDay(for: date("2026-05-03 06:00")),
            stages: [
                SleepStage(startDate: bedtime, endDate: bedtime.addingTimeInterval(15 * 60), type: .awake),
                SleepStage(
                    startDate: bedtime.addingTimeInterval(15 * 60),
                    endDate: date("2026-05-03 06:00"),
                    type: .core
                ),
            ]
        )
    }

    private func trendsFile(meals: [MealEvent]) -> CSVExportFile {
        CSVExporter.trendsFile(
            sessions: [session()],
            dailyCalories: [],
            dailyRestingHR: [],
            dailyHRV: [],
            sleepHeartRates: [:],
            meals: meals,
            calendar: calendar
        )
    }

    // MARK: - Trends export

    @Test func trendsExportCarriesTheNightsMealsOnTheSameRow() {
        let file = trendsFile(meals: [
            MealEvent(timestamp: date("2026-05-02 12:30"), note: "Chicken salad"),
            MealEvent(timestamp: date("2026-05-02 19:00"), note: "Pasta, garlic bread"),
        ])

        #expect(file.content.contains("meal_count,first_meal_time,last_meal_time,hours_last_meal_to_sleep,meals"))
        #expect(file.content.contains("2026-05-02T12:30:00Z|Chicken salad; 2026-05-02T19:00:00Z|Pasta, garlic bread"))
        // Onset is 22:15, last meal 19:00.
        #expect(file.content.contains(",2,2026-05-02T12:30:00Z,2026-05-02T19:00:00Z,3.25,"))
    }

    /// Semicolons and pipes would otherwise break the sub-format inside the
    /// `meals` cell.
    @Test func separatorsInsideANoteAreNeutralised() {
        let file = trendsFile(meals: [
            MealEvent(timestamp: date("2026-05-02 19:00"), note: "rice; beans | salsa")
        ])

        #expect(file.content.contains("2026-05-02T19:00:00Z|rice, beans / salsa"))
    }

    @Test func nightsWithNoMealsExportEmptyMealColumns() {
        #expect(trendsFile(meals: []).content.contains(",0,,,,"))
    }

    // MARK: - Meal window

    /// A snack after midnight belongs to the night it preceded, not the next
    /// one — the window closes at sleep onset rather than at midnight.
    @Test func aPostMidnightSnackCountsTowardTheNightItPreceded() {
        let bedtime = date("2026-05-03 01:00")
        let lateNight = SleepSession(
            nightDate: calendar.startOfDay(for: date("2026-05-03 08:00")),
            stages: [
                SleepStage(startDate: bedtime, endDate: date("2026-05-03 08:00"), type: .core)
            ]
        )

        let meals = MealSleepAnalyzer.meals(
            precedingSleepIn: lateNight,
            from: [MealEvent(timestamp: date("2026-05-03 00:30"), note: "Cereal")],
            calendar: calendar
        )

        #expect(meals.map(\.note) == ["Cereal"])
    }

    @Test func mealsAfterSleepOnsetAreExcluded() {
        let meals = MealSleepAnalyzer.meals(
            precedingSleepIn: session(),
            from: [MealEvent(timestamp: date("2026-05-03 07:00"), note: "Breakfast")],
            calendar: calendar
        )

        #expect(meals.isEmpty)
    }

    // MARK: - Daily export

    @Test func dailyExportAddsAMealRowPerEntry() {
        let file = CSVExporter.dailyFile(
            for: session(),
            meals: [
                MealEvent(timestamp: date("2026-05-02 12:30"), note: "Chicken salad"),
                MealEvent(timestamp: date("2026-05-02 19:00"), note: "Pasta"),
            ],
            calendar: calendar
        )
        let mealRows = file.content
            .split(separator: "\n")
            .filter { $0.hasPrefix("meal,") }
            .map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }

        #expect(file.content.contains(",stand_hours,source,note"))
        #expect(mealRows.count == 2)
        #expect(mealRows.map { $0[1] } == ["2026-05-03", "2026-05-03"])
        #expect(mealRows.map { $0[2] } == ["2026-05-02T12:30:00Z", "2026-05-02T19:00:00Z"])
        #expect(mealRows.compactMap(\.last) == ["Chicken salad", "Pasta"])
    }

    /// Every row has to line up with the header or the file will not parse.
    /// Parsed rather than split on commas, so a note containing one cannot make
    /// this pass or fail for the wrong reason.
    @Test func everyDailyRowMatchesTheHeaderWidth() {
        let file = CSVExporter.dailyFile(
            for: session(),
            meals: [MealEvent(timestamp: date("2026-05-02 19:00"), note: "Rice, beans, and \"salsa\"")],
            calendar: calendar
        )

        let widths = CSVReader.parse(file.content).map(\.count)

        #expect(widths.allSatisfy { $0 == widths[0] })
    }

    // MARK: - Escaping

    @Test func aCommaInANoteSurvivesTheTrendsExport() {
        let file = trendsFile(meals: [
            MealEvent(timestamp: date("2026-05-02 19:00"), note: "Rice, beans, and salsa")
        ])
        let rows = CSVReader.parse(file.content)
        let mealsColumn = rows[0].firstIndex(of: "meals")!

        #expect(rows[1].count == rows[0].count)
        #expect(rows[1][mealsColumn] == "2026-05-02T19:00:00Z|Rice, beans, and salsa")
    }

    @Test func aQuoteInANoteSurvivesTheTrendsExport() {
        let file = trendsFile(meals: [
            MealEvent(timestamp: date("2026-05-02 19:00"), note: "a \"big\" bowl, late")
        ])
        let rows = CSVReader.parse(file.content)
        let mealsColumn = rows[0].firstIndex(of: "meals")!

        #expect(rows[1][mealsColumn] == "2026-05-02T19:00:00Z|a \"big\" bowl, late")
    }

    @Test func aCommaInANoteSurvivesTheDailyExport() {
        let file = CSVExporter.dailyFile(
            for: session(),
            meals: [MealEvent(timestamp: date("2026-05-02 19:00"), note: "Chicken, rice, \"leftovers\"")],
            calendar: calendar
        )
        let rows = CSVReader.parse(file.content)

        #expect(rows.first(where: { $0.first == "meal" })?.last == "Chicken, rice, \"leftovers\"")
    }

    /// The in-app editor accepts multi-line notes, so a newline can reach the
    /// exporter. In the wide file it is flattened to keep the cell on one line;
    /// the daily file keeps the note verbatim, quoted.
    @Test func aNewlineInANoteIsFlattenedInTrendsAndKeptInDaily() {
        let note = "Curry\nlots of garlic"

        let trends = CSVReader.parse(trendsFile(meals: [
            MealEvent(timestamp: date("2026-05-02 19:00"), note: note)
        ]).content)
        let mealsColumn = trends[0].firstIndex(of: "meals")!
        #expect(trends[1][mealsColumn] == "2026-05-02T19:00:00Z|Curry lots of garlic")

        let daily = CSVReader.parse(CSVExporter.dailyFile(
            for: session(),
            meals: [MealEvent(timestamp: date("2026-05-02 19:00"), note: note)],
            calendar: calendar
        ).content)
        #expect(daily.first(where: { $0.first == "meal" })?.last == note)
    }
}

struct MealDeepLinkTests {
    @Test func theWidgetsLogURLIsRecognised() {
        #expect(MealDeepLink.isLogMeal(MealDeepLink.logMeal))
        #expect(MealDeepLink.isLogMeal(URL(string: "somnus://log-meal")!))
    }

    /// The app opens a sheet on this URL, so anything else must be ignored
    /// rather than silently treated as a meal.
    @Test func otherURLsAreIgnored() {
        #expect(!MealDeepLink.isLogMeal(URL(string: "somnus://trends")!))
        #expect(!MealDeepLink.isLogMeal(URL(string: "https://example.com/log-meal")!))
        #expect(!MealDeepLink.isLogMeal(URL(string: "othersleepapp://log-meal")!))
    }
}

/// A minimal RFC 4180 reader, so the export tests verify what a spreadsheet or
/// an analysis tool would actually read back rather than what the raw text
/// happens to contain.
enum CSVReader {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        while let character = pending ?? iterator.next() {
            pending = nil

            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }

            switch character {
            case "\"":
                inQuotes = true
            case ",":
                row.append(field)
                field = ""
            case "\n":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            default:
                field.append(character)
            }
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
