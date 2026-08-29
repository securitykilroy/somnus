import Foundation
import SwiftUI

/// A human-readable classification of how strongly two metrics move together,
/// derived from a Pearson r value. Thresholds follow the common rule-of-thumb
/// bands (Cohen-style) used for interpreting correlation coefficients.
enum CorrelationStrength {
    case negligible
    case weak
    case moderate
    case strong
    case veryStrong

    /// Classifies a Pearson r value into a strength + direction.
    nonisolated static func classify(_ r: Double) -> (strength: CorrelationStrength, label: String, color: Color) {
        let magnitude = abs(r)
        let strength: CorrelationStrength
        switch magnitude {
        case ..<0.1:  strength = .negligible
        case ..<0.3:  strength = .weak
        case ..<0.5:  strength = .moderate
        case ..<0.7:  strength = .strong
        default:      strength = .veryStrong
        }

        let directionWord = magnitude < 0.1 ? "" : (r > 0 ? "positive " : "negative ")
        let strengthWord: String
        switch strength {
        case .negligible: strengthWord = "No meaningful correlation"
        case .weak:       strengthWord = "Weak \(directionWord)correlation"
        case .moderate:   strengthWord = "Moderate \(directionWord)correlation"
        case .strong:     strengthWord = "Strong \(directionWord)correlation"
        case .veryStrong: strengthWord = "Very strong \(directionWord)correlation"
        }

        let color: Color
        switch (strength, r > 0) {
        case (.negligible, _):       color = .secondary
        case (_, true):              color = .green
        case (_, false):             color = .red
        }

        return (strength, strengthWord, color)
    }
}

enum CorrelationStatistics {
    nonisolated static func linearRegression(_ xs: [Double], _ ys: [Double]) -> (slope: Double, intercept: Double)? {
        guard xs.count == ys.count, xs.count >= 3 else { return nil }
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +), sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = xs.reduce(0) { $0 + $1 * $1 }
        let denom = n * sumX2 - sumX * sumX
        guard abs(denom) > 1e-10 else { return nil }
        let slope = (n * sumXY - sumX * sumY) / denom
        return (slope, (sumY - slope * sumX) / n)
    }

    nonisolated static func pearsonR(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 3 else { return nil }
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +), sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = xs.reduce(0) { $0 + $1 * $1 }
        let sumY2 = ys.reduce(0) { $0 + $1 * $1 }
        let numerator = n * sumXY - sumX * sumY
        let denominator = ((n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY)).squareRoot()
        guard abs(denominator) > 1e-10 else { return nil }
        return numerator / denominator
    }
}
