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
    @State private var saveFailed = false

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
                        // Bounded to the past: a meal cannot have been
                        // eaten later than now, and a future timestamp
                        // made the card read "Last meal -1m ago".
                        DatePicker("Time", selection: $timestamp, in: ...Date())
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
                        // The widget's intents raise an error when the shared
                        // container is unreachable; this used to dismiss as if
                        // it had saved, losing what was typed.
                        if mealStore.add(note: note, at: timestamp) {
                            dismiss()
                        } else {
                            saveFailed = true
                        }
                    }
                }
            }
            .onAppear { noteFocused = true }
            .alert("Could not save", isPresented: $saveFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Somnus could not reach its shared storage. Your entry is still here — try again in a moment.")
            }
        }
    }
}

#Preview {
    MealEntrySheet()
        .environment(MealStore())
}
