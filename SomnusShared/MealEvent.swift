import Foundation

/// A single eating occasion, recorded at whatever fidelity was convenient at
/// the time.
///
/// The note is free text and often empty — a widget tap records only that you
/// ate, which is deliberate. `timestamp` is the analytically useful part: the
/// gap between the last meal and sleep onset is what correlates with sleep,
/// and demanding a description before an entry can exist would cost more
/// entries than the descriptions are worth.
struct MealEvent: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var timestamp: Date
    var note: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        timestamp: Date,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var hasNote: Bool { !note.isEmpty }

    /// What to show wherever the entry needs a one-line label.
    var displayLabel: String {
        hasNote ? note : "Ate"
    }
}
