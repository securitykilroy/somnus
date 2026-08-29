import SwiftUI

/// The typing surface the widget cannot provide.
///
/// Opened by the `somnus://log-meal` deep link, it presents over whatever the
/// app is doing and takes the keyboard immediately, so the HealthKit load
/// running behind it never stands between you and the entry.
struct MealEntrySheet: View {
    @Environment(MealStore.self) private var mealStore
    @Environment(\.dismiss) private var dismiss

    @State private var note = ""
    @State private var timestamp = Date()
    @State private var adjustingTime = false
    @FocusState private var noteFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("What You Ate") {
                    TextField("Chicken curry, lots of garlic", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($noteFocused)
                        .submitLabel(.done)
                }

                Section {
                    if adjustingTime {
                        DatePicker("Time", selection: $timestamp)
                    } else {
                        // Collapsed by default: the time is right the vast
                        // majority of the time, and an expanded picker would
                        // push the text field under the keyboard.
                        Button {
                            adjustingTime = true
                        } label: {
                            LabeledContent("Time") {
                                Text(timestamp.formatted(date: .omitted, time: .shortened))
                            }
                        }
                        .tint(.primary)
                    }
                } footer: {
                    Text("Defaults to now. Tap to log something you ate earlier.")
                }
            }
            .navigationTitle("Log a Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        mealStore.add(note: note, at: timestamp)
                        dismiss()
                    }
                }
            }
            .onAppear { noteFocused = true }
        }
    }
}

#Preview {
    MealEntrySheet()
        .environment(MealStore())
}
