import SwiftUI

struct RecoveryScoreCardView: View {
    let score: RecoveryScore?

    private var scoreColor: Color {
        guard let score else { return .secondary }
        switch score.score {
        case 60...:   return .green
        case 40..<60: return .primary
        default:      return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recovery")
                .font(.headline)

            if let score {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int(score.score.rounded()))")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor)
                    Text(score.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
                }
                Text("Relative to your own HRV, resting heart rate, deep sleep, and continuity baseline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not enough data yet to compute a recovery score")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
