import Foundation

nonisolated extension TimeInterval {
    /// Sign is carried on the whole value rather than falling out of integer
    /// division. `-3660` used to give hours `-1` and minutes `-1`, skip the
    /// `hours > 0` branch and render as "-1m" — which the meal card then showed
    /// as "Last meal -1m ago" for anything dated in the future.
    var hoursAndMinutes: String {
        let totalMinutes = Int(abs(self) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let sign = self < 0 ? "-" : ""
        return hours > 0 ? "\(sign)\(hours)h \(minutes)m" : "\(sign)\(minutes)m"
    }

    var asHours: Double { self / 3600 }

    /// Single-unit duration for the tightest slots — the lock screen circular
    /// gauge, where "7h 12m" does not fit inside the ring.
    var compactDuration: String {
        let totalMinutes = Int(abs(self) / 60)
        let hours = totalMinutes / 60
        let sign = self < 0 ? "-" : ""
        return hours > 0 ? "\(sign)\(hours)h" : "\(sign)\(totalMinutes % 60)m"
    }
}

nonisolated extension Double {
    var percentString: String {
        "\(Int((self * 100).rounded()))%"
    }
}
