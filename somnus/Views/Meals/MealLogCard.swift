import SwiftUI

/// The in-app half of meal logging: mostly a correction surface.
///
/// Day to day the entries arrive from the widget or from Siri; what the app
/// adds is the ability to fix a time that was tapped late, attach a
/// description to a bare "Ate", or delete a mis-tap.
struct MealLogCard: View {
    @Environment(MealStore.self) private var mealStore
    @State private var draftNote = ""
    @State private var editing: MealEvent?

    private var todaysMeals: [MealEvent] {
        mealStore.events(on: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Meals")
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("What did you eat?", text: $draftNote)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit(logDraft)

                Button(action: logDraft) {
                    Label("Log", systemImage: "fork.knife")
                        .labelStyle(.iconOnly)
                        .frame(width: 24)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel("Log meal now")
            }

            if todaysMeals.isEmpty {
                Text("Nothing logged today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(todaysMeals) { meal in
                        Button {
                            editing = meal
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "fork.knife")
                                    .foregroundStyle(.teal)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(meal.displayLabel)
                                        .font(.subheadline.weight(.medium))
                                    Text(meal.timestamp.formatted(date: .omitted, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .sheet(item: $editing) { meal in
            MealEditSheet(meal: meal)
        }
    }

    private var subtitle: String {
        guard let last = mealStore.lastMeal else {
            return "Log roughly when you eat to compare it against your sleep"
        }
        let elapsed = Date().timeIntervalSince(last.timestamp)
        return "Last meal \(elapsed.hoursAndMinutes) ago"
    }

    private func logDraft() {
        mealStore.add(note: draftNote)
        draftNote = ""
    }
}

struct MealEditSheet: View {
    @Environment(MealStore.self) private var mealStore
    @Environment(\.dismiss) private var dismiss

    let meal: MealEvent

    @State private var note: String
    @State private var timestamp: Date

    init(meal: MealEvent) {
        self.meal = meal
        _note = State(initialValue: meal.note)
        _timestamp = State(initialValue: meal.timestamp)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What You Ate") {
                    TextField("Description", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section("When") {
                    DatePicker("Time", selection: $timestamp)
                }
                Section {
                    Button("Delete Entry", role: .destructive) {
                        mealStore.delete(id: meal.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        mealStore.update(id: meal.id, note: note, timestamp: timestamp)
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    MealLogCard()
        .environment(MealStore())
        .padding()
}
