//  BuildYourOwnRoutineView.swift
//  Bodyweight WorkoutRandomizer
//
//  A manual routine builder: pick any exercise, stretch, or custom "My Exercise", set its
//  duration/rest/order by hand, and save the result. This deliberately does not introduce a
//  new player or detail screen — the output is a plain SavedWorkoutRoutine, so it plays back,
//  edits, and deletes through the exact same SavedRoutineStore / SavedRoutineDetailView
//  pipeline "My Routines" already uses.

import SwiftUI

struct BuildYourOwnRoutineView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var catalog = ExerciseCatalog.shared
    @State private var customExerciseStore = CustomExerciseStore.shared

    @State private var routineName = ""
    @State private var routineDescription = ""
    @State private var items: [SavedRoutineExercise] = []
    @State private var selectedColorName = "purple"
    @State private var selectedIcon = "figure.mixed.cardio"
    @State private var showingPicker = false

    private static let colorOptions: [(name: String, color: Color)] = [
        ("purple", .purple), ("blue", .blue), ("green", .green), ("orange", .orange),
        ("red", .red), ("teal", .teal), ("indigo", .indigo), ("pink", .pink), ("yellow", .yellow)
    ]
    private static let iconOptions = [
        "figure.mixed.cardio", "figure.core.training", "figure.strengthtraining.traditional",
        "figure.flexibility", "star.fill", "bolt.fill", "flame.fill", "figure.run"
    ]

    private var canSave: Bool {
        !routineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !items.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Routine Name", text: $routineName)
                    TextField("Description (optional)", text: $routineDescription, axis: .vertical)
                }

                Section("Appearance") {
                    OverflowScrollRow(items: Self.colorOptions.map(\.name)) { name in
                        let color = Self.colorOptions.first { $0.name == name }?.color ?? .purple
                        Button { selectedColorName = name } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    if selectedColorName == name {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    OverflowScrollRow(items: Self.iconOptions) { icon in
                        Button { selectedIcon = icon } label: {
                            Image(systemName: icon)
                                .font(.title3)
                                .frame(width: 36, height: 36)
                                .background(selectedIcon == icon ? accentColor : Color.gray.opacity(0.15))
                                .foregroundStyle(selectedIcon == icon ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Add Exercise or Stretch", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Your Routine")
                } footer: {
                    if items.isEmpty {
                        Text("Add exercises, then set each one's duration, rest, and order below.")
                    }
                }

                ForEach(Array(items.enumerated()), id: \.element.id) { index, _ in
                    Section {
                        builderRow(index: index)
                    }
                }
            }
            .navigationTitle("Build Your Own")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerSheet(catalog: catalog, customExercises: customExerciseStore.exercises) { name, singleSided, isStretch in
                    items.append(SavedRoutineExercise(
                        name: name,
                        duration: isStretch ? 20 : 30,
                        restDuration: isStretch ? 0 : 10,
                        singleSided: singleSided,
                        restAfterEachSide: false,
                        moveType: isStretch ? .hold : .move
                    ))
                }
            }
        }
    }

    private var accentColor: Color {
        Self.colorOptions.first { $0.name == selectedColorName }?.color ?? .purple
    }

    @ViewBuilder
    private func builderRow(index: Int) -> some View {
        let item = items[index]
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                HStack(spacing: 14) {
                    Button {
                        moveItem(at: index, offset: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(index == 0)

                    Button {
                        moveItem(at: index, offset: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(index == items.count - 1)

                    Button(role: .destructive) {
                        items.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Picker("Type", selection: binding(for: index, \.moveType)) {
                Text("Hold").tag(SavedMoveType.hold)
                Text("Move").tag(SavedMoveType.move)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Stepper(value: binding(for: index, \.duration), in: 5...300, step: 5) {
                HStack {
                    Text(item.singleSided ? "Duration (per side)" : "Duration")
                    Spacer()
                    Text("\(item.duration)s")
                        .foregroundStyle(.secondary)
                }
            }

            Stepper(value: binding(for: index, \.restDuration), in: 0...120, step: 5) {
                HStack {
                    Text("Rest After")
                    Spacer()
                    Text("\(item.restDuration)s")
                        .foregroundStyle(.secondary)
                }
            }

            if item.singleSided {
                Toggle("Rest Between Sides", isOn: binding(for: index, \.restAfterEachSide))
            }
        }
        .padding(.vertical, 4)
    }

    /// A two-way binding into one field of `items[index]`, so Steppers/Toggles/Pickers in the
    /// row can edit it directly without each needing its own get/set boilerplate.
    private func binding<T>(for index: Int, _ keyPath: WritableKeyPath<SavedRoutineExercise, T>) -> Binding<T> {
        Binding(
            get: { items[index][keyPath: keyPath] },
            set: { items[index][keyPath: keyPath] = $0 }
        )
    }

    private func moveItem(at index: Int, offset: Int) {
        let target = index + offset
        guard items.indices.contains(index), items.indices.contains(target) else { return }
        items.swapAt(index, target)
    }

    private func save() {
        let routine = SavedWorkoutRoutine(
            name: routineName.trimmingCharacters(in: .whitespacesAndNewlines),
            routineDescription: routineDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            source: "You",
            sourceURL: "",
            exercises: items,
            accentColorName: selectedColorName,
            systemImage: selectedIcon
        )
        SavedRoutineStore.shared.save(routine)
        dismiss()
    }
}

/// Full-catalog exercise picker for the builder: every regular exercise, every stretch, and
/// (only when any exist) the user's own "My Exercises" — mirroring how ExercisesView groups
/// regular vs. stretch focus areas.
private struct ExercisePickerSheet: View {
    let catalog: ExerciseCatalog
    let customExercises: [UserExercise]
    /// (name, singleSided, isStretch) — isStretch seeds a Hold default; a regular exercise
    /// seeds a Move default. Either can be changed afterward in the builder row.
    let onPick: (String, Bool, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private static let stretchAreaNames: Set<String> = [
        "Morning Stretches", "Evening Recovery", "Cool Down", "Warm-Up: Hips", "Warm-Up: Full Body"
    ]

    private var regularAreas: [String] {
        catalog.focusAreas.filter { !Self.stretchAreaNames.contains($0) }.sorted()
    }

    private var stretchAreas: [String] {
        catalog.focusAreas.filter { Self.stretchAreaNames.contains($0) }.sorted()
    }

    private func items(for area: String) -> [Exercise] {
        let all = (catalog.exercises[area] ?? [:]).values.flatMap { $0 }
        let filtered = searchText.isEmpty
            ? all
            : all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        return filtered.sorted { $0.name < $1.name }
    }

    private var filteredCustomExercises: [UserExercise] {
        searchText.isEmpty
            ? customExercises
            : customExercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !filteredCustomExercises.isEmpty {
                    Section("My Exercises") {
                        ForEach(filteredCustomExercises) { custom in
                            Button {
                                onPick(custom.name, false, false)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(custom.name)
                                    Spacer()
                                    Text(custom.focusArea)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }

                ForEach(regularAreas, id: \.self) { area in
                    let list = items(for: area)
                    if !list.isEmpty {
                        Section(area) {
                            ForEach(list, id: \.name) { exercise in
                                Button {
                                    onPick(exercise.name, exercise.singleSided, false)
                                    dismiss()
                                } label: {
                                    Text(exercise.name)
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                }

                ForEach(stretchAreas, id: \.self) { area in
                    let list = items(for: area)
                    if !list.isEmpty {
                        Section {
                            ForEach(list, id: \.name) { exercise in
                                Button {
                                    onPick(exercise.name, exercise.singleSided, true)
                                    dismiss()
                                } label: {
                                    Text(exercise.name)
                                }
                                .foregroundStyle(.primary)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: "figure.cooldown")
                                Text(area)
                            }
                            .foregroundStyle(.teal)
                        }
                    }
                }
            }
#if os(iOS)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
#else
            .searchable(text: $searchText)
#endif
            .navigationTitle("Add Exercise")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
