import Foundation

extension TimeInterval {
    var hoursAndMinutes: String {
        let totalMinutes = Int(self / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    var asHours: Double { self / 3600 }
}

extension Double {
    var percentString: String {
        "\(Int((self * 100).rounded()))%"
    }
}
