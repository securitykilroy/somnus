import SwiftUI

struct DebtCardView: View {
    let title: String
    var subtitle: String? = nil
    let debt: TimeInterval  // positive = deficit, negative = surplus

    private var isDeficit: Bool { debt > 0 }
    private var absDebt: TimeInterval { abs(debt) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text((isDeficit ? "-" : "+") + absDebt.hoursAndMinutes)
                .font(.title2.bold())
                .foregroundStyle(isDeficit ? .red : .green)
            Text(isDeficit ? "deficit" : "surplus")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SummaryStatCard: View {
    let title: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
