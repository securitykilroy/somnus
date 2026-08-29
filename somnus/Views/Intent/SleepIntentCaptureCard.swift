import SwiftUI

struct SleepIntentCaptureCard: View {
    @Environment(SleepIntentStore.self) private var intentStore
    @State private var loggingError: Error?

    private var recentEvents: [SleepIntentEvent] {
        Array(intentStore.events.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sleep Intent")
                        .font(.headline)
                    Text("Log when you start trying to sleep")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Button {
                log(.tryingToSleep)
            } label: {
                Label("Trying to sleep", systemImage: SleepIntentKind.tryingToSleep.systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if let loggingError {
                Label(loggingError.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if recentEvents.isEmpty {
                Text("No intent events logged yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(recentEvents) { event in
                        HStack(spacing: 10) {
                            Image(systemName: event.kind.systemImage)
                                .foregroundStyle(event.kind == .tryingToSleep ? .indigo : .orange)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.kind.displayName)
                                    .font(.subheadline.weight(.medium))
                                Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func log(_ kind: SleepIntentKind) {
        do {
            try intentStore.add(kind: kind)
            loggingError = nil
        } catch {
            loggingError = error
        }
    }
}
