import Foundation
import Observation
import WidgetKit

/// The app's view onto the shared meal log.
///
/// Thin on purpose: the file in `MealLogStore` is the source of truth and the
/// widget writes to it directly, so this holds no state the log does not — it
/// just republishes it for SwiftUI and pushes a widget reload after each edit.
@MainActor
@Observable
final class MealStore {
    private let log: MealLogStore

    private(set) var events: [MealEvent] = []

    init(log: MealLogStore = MealLogStore()) {
        self.log = log
        reload()
    }

    /// Called on foreground as well as after edits: a widget tap or a Siri
    /// phrase can have appended entries while the app sat in the background.
    func reload() {
        events = log.read()
    }

    func events(on date: Date, calendar: Calendar = .current) -> [MealEvent] {
        events.filter { calendar.isDate($0.timestamp, inSameDayAs: date) }
    }

    var lastMeal: MealEvent? { events.first }

    @discardableResult
    func add(note: String = "", at timestamp: Date = Date()) -> Bool {
        let added = log.append(note: note, at: timestamp) != nil
        finishEdit()
        return added
    }

    @discardableResult
    func update(id: UUID, note: String? = nil, timestamp: Date? = nil) -> Bool {
        let updated = log.update(id: id, note: note, timestamp: timestamp)
        finishEdit()
        return updated
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        let deleted = log.delete(id: id)
        finishEdit()
        return deleted
    }

    private func finishEdit() {
        reload()
        WidgetCenter.shared.reloadTimelines(ofKind: MealWidgetKind.value)
    }
}
