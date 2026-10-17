//  BuildYourOwnRoutineView.swift
//  Bodyweight WorkoutRandomizer
//
//  A manual routine builder: pick any exercise, stretch, or custom "My Exercise", set its
//  duration/rest/order by hand, and save the result. This deliberately does not introduce a
//  new player or detail screen — the output is a plain SavedWorkoutRoutine, so it plays back,
//  edits, and deletes through the exact same SavedRoutineStore / SavedRoutineDetailView
//  pipeline "My Routines" already uses.

import SwiftUI

/// The exercises queued for "Build Your Own," shared across the Exercises, My Exercises, and
/// builder tabs — swiping or long-pressing a row anywhere appends here, and the builder (and
/// the mini-player-style queue bar) both read from the same instance.
@MainActor
@Observable
final class RoutineBuilderQueue {
    static let shared = RoutineBuilderQueue()
    private static let storageKey = "routineBuilderQueue_v1"

    var items: [SavedRoutineExercise] = [] {
        didSet { persist() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([SavedRoutineExercise].self, from: data) {
            items = decoded
        }
    }

    /// isStretch seeds a Hold default at 20s with no rest; a regular exercise seeds a Move
    /// default at 30s/10s rest. Either can be changed afterward in the builder row.
    func add(name: String, singleSided: Bool, isStretch: Bool) {
        items.append(SavedRoutineExercise(
            name: name,
            duration: isStretch ? 20 : 30,
            restDuration: isStretch ? 0 : 10,
            singleSided: singleSided,
            restAfterEachSide: false,
            moveType: isStretch ? .hold : .move
        ))
    }

    func clear() {
        items = []
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

struct BuildYourOwnRoutineView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var catalog = ExerciseCatalog.shared
    @State private var customExerciseStore = CustomExerciseStore.shared
    @State private var queue = RoutineBuilderQueue.shared

    @State private var routineName = ""
    @State private var routineDescription = ""
    @State private var category = ""
    @State private var selectedColorName = "purple"
    @State private var selectedIcon = "figure.mixed.cardio"
    @State private var showingPicker = false
    @State private var showingClearConfirmation = false

    private static let colorOptions: [(name: String, color: Color)] = [
        ("purple", .purple), ("blue", .blue), ("green", .green), ("orange", .orange),
        ("red", .red), ("teal", .teal), ("indigo", .indigo), ("pink", .pink), ("yellow", .yellow)
    ]
    private static let iconOptions = [
        "figure.mixed.cardio", "figure.core.training", "figure.strengthtraining.traditional",
        "figure.flexibility", "star.fill", "bolt.fill", "flame.fill", "figure.run"
    ]

    /// Longest a hold at each difficulty is realistically sustainable. Levels not listed
    /// (Beginner, Medium) get no cap — this is about isometric holds getting harder to sustain
    /// as difficulty rises, not a general duration limit.
    private static let recommendedMaxHoldDuration: [String: Int] = [
        "Hard": 90,
        "Expert/Advanced": 45
    ]

    private var canSave: Bool {
        !routineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !queue.items.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Routine Name", text: $routineName)
                    TextField("Description (optional)", text: $routineDescription, axis: .vertical)
                }

                Section {
                    CategoryField(text: $category)
                } header: {
                    Text("Folder")
                } footer: {
                    Text("Where it's filed in the Saved tab. Leave blank for Uncategorized.")
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
                    if !queue.items.isEmpty {
                        Button(role: .destructive) {
                            showingClearConfirmation = true
                        } label: {
                            Label("Clear All", systemImage: "trash")
                        }
                    }
                } header: {
                    Text("Your Routine")
                } footer: {
                    if queue.items.isEmpty {
                        Text("Add exercises, then set each one's duration, rest, and order below.")
                    }
                }

                ForEach(queue.items) { item in
                    Section {
                        builderRow(for: item)
                    }
                }
            }
            .navigationTitle("Build Your Own")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .confirmationDialog(
                "Clear all exercises from this routine?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) { queue.clear() }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerSheet(catalog: catalog, customExercises: customExerciseStore.exercises) { name, singleSided, isStretch in
                    queue.add(name: name, singleSided: singleSided, isStretch: isStretch)
                }
            }
        }
    }

    private var accentColor: Color {
        Self.colorOptions.first { $0.name == selectedColorName }?.color ?? .purple
    }

    @ViewBuilder
    private func builderRow(for item: SavedRoutineExercise) -> some View {
        let index = queue.items.firstIndex(where: { $0.id == item.id }) ?? 0
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                HStack(spacing: 14) {
                    Button {
                        moveItem(item, offset: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(index == 0)

                    Button {
                        moveItem(item, offset: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(index == queue.items.count - 1)

                    Button(role: .destructive) {
                        queue.items.removeAll { $0.id == item.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Picker("Type", selection: binding(for: item, \.moveType)) {
                Text("Hold").tag(SavedMoveType.hold)
                Text("Move").tag(SavedMoveType.move)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Stepper(value: binding(for: item, \.duration), in: 5...300, step: 5) {
                HStack {
                    Text(item.singleSided ? "Duration (per side)" : "Duration")
                    Spacer()
                    Text("\(item.duration)s")
                        .foregroundStyle(.secondary)
                }
            }

            Stepper(value: binding(for: item, \.restDuration), in: 0...120, step: 5) {
                HStack {
                    Text("Rest After")
                    Spacer()
                    Text("\(item.restDuration)s")
                        .foregroundStyle(.secondary)
                }
            }

            if item.singleSided {
                Toggle("Rest Between Sides", isOn: binding(for: item, \.restAfterEachSide))
            }

            if let warning = durationWarning(for: item) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    /// The difficulty level the exercise is cataloged under, checked against both the bundled
    /// catalog and the user's own "My Exercises", or nil for an unrecognized name.
    private func difficulty(for exerciseName: String) -> String? {
        if let custom = customExerciseStore.exercises.first(where: { $0.name == exerciseName }) {
            return custom.difficulty
        }
        for difficultyDict in catalog.exercises.values {
            for (level, exercises) in difficultyDict where exercises.contains(where: { $0.name == exerciseName }) {
                return level
            }
        }
        return nil
    }

    private func durationWarning(for item: SavedRoutineExercise) -> String? {
        guard item.moveType == .hold,
              let level = difficulty(for: item.name),
              let cap = Self.recommendedMaxHoldDuration[level],
              item.duration > cap else { return nil }
        return "\(level) holds are tough to sustain this long — consider a shorter duration or an easier variation."
    }

    /// A two-way binding into one field of the item matching `item.id`, resolved fresh on every
    /// get/set rather than captured as a fixed array position — a captured index can go stale
    /// (and crash on an out-of-bounds access) the moment another row is removed, since `List`/
    /// `Form` row content can still be evaluated mid-removal-animation against the shrunk array.
    private func binding<T>(for item: SavedRoutineExercise, _ keyPath: WritableKeyPath<SavedRoutineExercise, T>) -> Binding<T> {
        Binding(
            get: {
                queue.items.first(where: { $0.id == item.id })?[keyPath: keyPath] ?? item[keyPath: keyPath]
            },
            set: { newValue in
                guard let idx = queue.items.firstIndex(where: { $0.id == item.id }) else { return }
                queue.items[idx][keyPath: keyPath] = newValue
            }
        )
    }

    private func moveItem(_ item: SavedRoutineExercise, offset: Int) {
        guard let index = queue.items.firstIndex(where: { $0.id == item.id }) else { return }
        let target = index + offset
        guard queue.items.indices.contains(target) else { return }
        queue.items.swapAt(index, target)
    }

    private func save() {
        let routine = SavedWorkoutRoutine(
            name: routineName.trimmingCharacters(in: .whitespacesAndNewlines),
            routineDescription: routineDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            source: "You",
            sourceURL: "",
            exercises: queue.items,
            accentColorName: selectedColorName,
            systemImage: selectedIcon,
            category: RoutineFolders.normalizedName(category)
        )
        SavedRoutineStore.shared.save(routine)
        queue.clear()
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

/// Music/Podcasts-style mini-player bar: shows what's queued for "Build Your Own" and opens the
/// builder on tap. Shown above the tab bar — via the system bottom accessory on iOS 26+, or a
/// `safeAreaInset` on each tab's own content as a fallback elsewhere (see RootTabView.swift).
struct RoutineQueueBar: View {
    let queue: RoutineBuilderQueue
    let onTap: () -> Void

    private var totalSeconds: Int {
        queue.items.reduce(0) { $0 + $1.totalSeconds }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "text.badge.plus")
                    .font(.headline)
                    .foregroundStyle(.purple)
                Text("\(queue.items.count) \(queue.items.count == 1 ? "exercise" : "exercises") · \(SavedWorkoutRoutine.formatDuration(totalSeconds))")
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
