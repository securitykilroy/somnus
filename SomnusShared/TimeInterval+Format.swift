import Foundation

extension TimeInterval {
    var hoursAndMinutes: String {
        let totalMinutes = Int(self / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    var asHours: Double { self / 3600 }

    /// Single-unit duration for the tightest slots — the lock screen circular
    /// gauge, where "7h 12m" does not fit inside the ring.
    var compactDuration: String {
        let totalMinutes = Int(self / 60)
        let hours = totalMinutes / 60
        return hours > 0 ? "\(hours)h" : "\(totalMinutes % 60)m"
    }
}

extension Double {
    var percentString: String {
        "\(Int((self * 100).rounded()))%"
    }
}
