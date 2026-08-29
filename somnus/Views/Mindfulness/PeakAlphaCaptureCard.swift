import SwiftUI

struct PeakAlphaCaptureCard: View {
    @Environment(PeakAlphaStore.self) private var store
    @State private var date = Date()
    @State private var valueText = ""
    @State private var isPickingDate = false
    @State private var loggingError: Error?
    @FocusState private var isValueFocused: Bool

    private var recentEntries: [PeakAlphaEntry] {
        Array(store.entries.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Peak Alpha")
                    .font(.headline)
                Text("Log readings from the Muse app to track them alongside sleep and recovery")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    isValueFocused = false
                    withAnimation(.snappy) {
                        isPickingDate.toggle()
                    }
                } label: {
                    HStack {
                        Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        Spacer()
                        Image(systemName: isPickingDate ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.bordered)

                if isPickingDate {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .onChange(of: date) { _, _ in
                            withAnimation(.snappy) {
                                isPickingDate = false
                            }
                        }
                }
            }

            HStack {
                TextField("Peak Alpha value", text: $valueText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .focused($isValueFocused)

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(Double(valueText) == nil || !store.isReady)
            }

            if let loggingError {
                Label(loggingError.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if recentEntries.isEmpty {
                Text("No Peak Alpha readings logged yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(recentEntries) { entry in
                        HStack(spacing: 10) {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundStyle(.purple)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.value.formatted(.number.precision(.fractionLength(0...2))))
                                    .font(.subheadline.weight(.medium))
                                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                remove(entry)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isValueFocused = false
                }
            }
        }
        .task {
            try? await store.loadAsync()
        }
    }

    private func save() {
        guard let value = Double(valueText) else { return }
        do {
            try store.add(date: date, value: value)
            valueText = ""
            isValueFocused = false
            isPickingDate = false
            loggingError = nil
        } catch {
            loggingError = error
        }
    }

    private func remove(_ entry: PeakAlphaEntry) {
        do {
            try store.remove(entry)
            loggingError = nil
        } catch {
            loggingError = error
        }
    }
}
