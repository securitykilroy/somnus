import Foundation

/// A manually logged Peak Alpha reading from the Muse app, which keeps that
/// metric in its own store rather than publishing it to HealthKit.
struct PeakAlphaEntry: Identifiable, Hashable, Codable {
    let id: UUID
    let date: Date
    let value: Double
    let note: String?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        value: Double,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.date = date
        self.value = value
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    var day: Date {
        Calendar.current.startOfDay(for: date)
    }
}
