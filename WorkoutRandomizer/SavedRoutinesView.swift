import SwiftUI
import AVKit
internal import UniformTypeIdentifiers
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(HealthKit)
import HealthKit
#endif

// MARK: - Models

nonisolated enum SavedMoveType: String, Codable {
    case hold = "Hold"
    case move = "Move"
}

nonisolated struct SavedRoutineExercise: Identifiable, Codable {
    var id = UUID()
    let name: String
    var duration: Int           // work/hold seconds per side
    var restDuration: Int       // rest after exercise (or after each side if restAfterEachSide)
    var singleSided: Bool
    var restAfterEachSide: Bool // for single-sided: rest after L and after R separately
    var moveType: SavedMoveType

    init(
        name: String,
        duration: Int,
        restDuration: Int = 0,
        singleSided: Bool = false,
        restAfterEachSide: Bool = false,
        moveType: SavedMoveType = .hold
    ) {
        self.name = name
        self.duration = duration
        self.restDuration = restDuration
        self.singleSided = singleSided
        self.restAfterEachSide = restAfterEachSide
        self.moveType = moveType
    }

    var totalSeconds: Int {
        let sides = singleSided ? 2 : 1
        let work = duration * sides
        let rest = (singleSided && restAfterEachSide) ? restDuration * 2 : restDuration
        return work + rest
    }
}

/// What kind of session a routine is, when that can't be inferred from its exercises. Stretch
/// routines mix holds and moving drills (Cat-Cow), so the hold-vs-move ratio alone would misfile
/// them as a workout when recording to Apple Health. `core` and `cardio` remember that a saved
/// workout was built from only those focus areas, which is what the live generator logs it by.
nonisolated enum SavedRoutineKind: String, Codable {
    case workout
    case stretch
    case core
    case cardio

    private static let coreAreas: Set<String> = ["Core", "Core: Strength"]
    private static let cardioAreas: Set<String> = ["Cardio"]
    private static let stretchAreas: Set<String> = [
        "Morning Stretches", "Evening Recovery", "Cool Down", "Warm-Up: Hips", "Warm-Up: Full Body"
    ]

    /// The kind a generated session falls into, from the focus areas that built it. Anything
    /// that isn't purely one of these is a general workout, logged by its Intention instead.
    static func forFocusAreas(_ areas: Set<String>) -> SavedRoutineKind {
        guard !areas.isEmpty else { return .workout }
        if areas.isSubset(of: coreAreas) { return .core }
        if areas.isSubset(of: cardioAreas) { return .cardio }
        if areas.isSubset(of: stretchAreas) { return .stretch }
        return .workout
    }

#if canImport(HealthKit)
    /// The activity this kind is always logged as, or nil when the Intention decides.
    var healthKitActivityType: HKWorkoutActivityType? {
        switch self {
        case .stretch: return .flexibility
        case .core: return .coreTraining
        case .cardio: return .mixedCardio
        case .workout: return nil
        }
    }
#endif
}

nonisolated struct SavedWorkoutRoutine: Identifiable, Codable {
    var id = UUID()
    let name: String
    let routineDescription: String
    let source: String
    let sourceURL: String
    var exercises: [SavedRoutineExercise]
    let accentColorName: String
    let systemImage: String
    /// The folder this routine is filed under. Optional (not defaulted) so routines saved by
    /// earlier versions still decode: nil reads as Uncategorized.
    var category: String? = nil
    var kind: SavedRoutineKind? = nil

    var accentColor: Color {
        switch accentColorName {
        case "yellow":  return .yellow
        case "orange":  return .orange
        case "indigo":  return .indigo
        case "purple":  return .purple
        case "green":   return .green
        case "teal":    return .teal
        case "red":     return .red
        case "pink":    return .pink
        default:        return .blue
        }
    }

    var totalDurationSeconds: Int {
        exercises.reduce(0) { $0 + $1.totalSeconds }
    }

    var formattedDuration: String {
        Self.formatDuration(totalDurationSeconds)
    }

    static func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let sec = seconds % 60
        return sec == 0 ? "\(m) min" : "\(m)m \(sec)s"
    }

    /// True for a stretch/mobility session. A routine tagged with a kind says so outright; an
    /// untagged one (built by hand, or saved before kinds existed) is judged by its hold-vs-move
    /// ratio — mostly holds reads as stretching. Stretch sessions have no Intention and no HR-zone
    /// target, so the detail screen and recap leave both out.
    var isFlexibilitySession: Bool {
        guard !exercises.isEmpty else { return false }
        if let kind { return kind == .stretch }
        let holds = exercises.filter { $0.moveType == .hold }.count
        return Double(holds) / Double(exercises.count) >= 0.8
    }

#if canImport(HealthKit)
    /// Classifies the routine for HealthKit: a tagged kind wins, then the hold-vs-move ratio for
    /// untagged routines, and otherwise whatever Intention the person picked before starting —
    /// the same order `WorkoutPlayerView.resolvedActivityType` uses for live workouts.
    func resolvedActivityType(intention: WorkoutIntention) -> HKWorkoutActivityType {
        guard !exercises.isEmpty else { return .other }
        if let fixed = kind?.healthKitActivityType { return fixed }
        if isFlexibilitySession { return .flexibility }
        return intention.healthKitActivityType
    }
#endif
}

// MARK: - Folders

/// A folder is not stored anywhere — it's just the set of routines that share a category name.
/// So a folder exists only while it has routines (built-in ones always do), and there's nothing
/// to keep in sync when a routine is saved, moved, or deleted.
struct RoutineFolder: Identifiable {
    let name: String
    let routines: [SavedWorkoutRoutine]
    let isBuiltIn: Bool

    var id: String { RoutineFolders.key(name) }
    var isUncategorized: Bool { id == RoutineFolders.key(RoutineFolders.uncategorizedName) }
}

enum RoutineFolders {
    static let uncategorizedName = "Uncategorized"
    /// Built-in folders always appear, and a user routine saved under the same name joins them.
    static let builtInNames = ["Stretches", "Core"]

    /// Comparison key: case-, spacing- and edge-whitespace-insensitive, so "core", "Core " and
    /// "CORE" all land in one folder instead of three.
    static func key(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// The tidied spelling to store, or nil when there's nothing to file under (blank, or the
    /// literal "Uncategorized", which is what nil already means).
    static func normalizedName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let tidy = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !tidy.isEmpty, key(tidy) != key(uncategorizedName) else { return nil }
        return tidy
    }

    /// Built-in folders (fixed order) and user folders (alphabetical, Uncategorized last, only
    /// when non-empty). Within a folder, built-in routines come first. A folder's display name
    /// is the first spelling seen, except built-ins, which always use their canonical name.
    static func folders(
        preloaded: [SavedWorkoutRoutine],
        user: [SavedWorkoutRoutine]
    ) -> (builtIn: [RoutineFolder], user: [RoutineFolder]) {
        var names: [String: String] = [:]
        var buckets: [String: [SavedWorkoutRoutine]] = [:]
        for routine in preloaded + user {
            let display = normalizedName(routine.category) ?? uncategorizedName
            let k = key(display)
            if names[k] == nil { names[k] = display }
            buckets[k, default: []].append(routine)
        }

        let builtInKeys = Set(builtInNames.map { key($0) })
        let uncategorizedKey = key(uncategorizedName)

        let builtIn = builtInNames.map {
            RoutineFolder(name: $0, routines: buckets[key($0)] ?? [], isBuiltIn: true)
        }
        var userFolders = buckets.keys
            .filter { !builtInKeys.contains($0) && $0 != uncategorizedKey }
            .sorted { (names[$0] ?? "").localizedCaseInsensitiveCompare(names[$1] ?? "") == .orderedAscending }
            .map { RoutineFolder(name: names[$0] ?? $0, routines: buckets[$0] ?? [], isBuiltIn: false) }
        if let loose = buckets[uncategorizedKey], !loose.isEmpty {
            userFolders.append(RoutineFolder(name: uncategorizedName, routines: loose, isBuiltIn: false))
        }
        return (builtIn, userFolders)
    }

    /// Names worth offering as one-tap choices when filing a routine.
    static func suggestedNames(user: [SavedWorkoutRoutine]) -> [String] {
        let grouped = folders(preloaded: [], user: user)
        return builtInNames + grouped.user.filter { !$0.isUncategorized }.map(\.name)
    }

    static func renaming(_ routines: [SavedWorkoutRoutine], from old: String, to new: String) -> [SavedWorkoutRoutine] {
        let oldKey = key(old)
        let newName = normalizedName(new)
        return routines.map { routine in
            guard key(normalizedName(routine.category) ?? uncategorizedName) == oldKey else { return routine }
            var moved = routine
            moved.category = newName
            return moved
        }
    }

    static func removing(_ routines: [SavedWorkoutRoutine], category: String) -> [SavedWorkoutRoutine] {
        let target = key(category)
        return routines.filter { key(normalizedName($0.category) ?? uncategorizedName) != target }
    }
}

// MARK: - Saved Routine Store

@MainActor
@Observable
final class SavedRoutineStore {
    static let shared = SavedRoutineStore()
    private static let storageKey = "userSavedRoutines_v1"

    private(set) var routines: [SavedWorkoutRoutine] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([SavedWorkoutRoutine].self, from: data) {
            routines = decoded
        }
    }

    func save(_ routine: SavedWorkoutRoutine) {
        if let idx = routines.firstIndex(where: { $0.id == routine.id }) {
            routines[idx] = routine
        } else {
            routines.append(routine)
        }
        persist()
    }

    func delete(at offsets: IndexSet) {
        routines.remove(atOffsets: offsets)
        persist()
    }

    func delete(id: UUID) {
        routines.removeAll { $0.id == id }
        persist()
    }

    func move(_ id: UUID, toCategory category: String?) {
        guard let idx = routines.firstIndex(where: { $0.id == id }) else { return }
        routines[idx].category = RoutineFolders.normalizedName(category)
        persist()
    }

    func renameCategory(from old: String, to new: String) {
        routines = RoutineFolders.renaming(routines, from: old, to: new)
        persist()
    }

    func deleteCategory(_ category: String) {
        routines = RoutineFolders.removing(routines, category: category)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(routines) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

// MARK: - Pre-loaded Athlean-X Routines

enum PreloadedRoutines {
    static let all: [SavedWorkoutRoutine] = [morningStretches, bedtimeStretches, absWorkout]

    static let morningStretches = SavedWorkoutRoutine(
        name: "5 Stretches Every Morning",
        routineDescription: "A full-body morning stretch sequence to loosen up your hips, back, and lower body. Do this before you start your day.",
        source: "Athlean-X",
        sourceURL: "https://youtu.be/eU2y-i7mt5Q?si=3pNLFzsHEhxZgU3M",
        exercises: [
            SavedRoutineExercise(name: "Squat Fold",            duration: 60, singleSided: false, moveType: .hold),
            SavedRoutineExercise(name: "Side Bridge & Reach",   duration: 30, singleSided: true,  moveType: .hold),
            SavedRoutineExercise(name: "QL Pull Through",       duration: 30, singleSided: true,  moveType: .hold),
            SavedRoutineExercise(name: "Hip Switch & Lean",     duration: 30, singleSided: true,  moveType: .hold),
            SavedRoutineExercise(name: "London Bridge",         duration: 30, singleSided: true,  moveType: .move),
        ],
        accentColorName: "yellow",
        systemImage: "sunrise.fill",
        category: "Stretches",
        kind: .stretch
    )

    static let bedtimeStretches = SavedWorkoutRoutine(
        name: "Do This Right Before Bed",
        routineDescription: "A calming evening stretch routine to release tension and prepare your body for sleep.",
        source: "Athlean-X",
        sourceURL: "https://youtu.be/0JeQlfQ5iCg?si=_xYp3xxabq-H0omR",
        exercises: [
            SavedRoutineExercise(name: "Calf & Hamstring Wall Stretch", duration: 30, singleSided: true,  moveType: .hold),
            SavedRoutineExercise(name: "Child's Pose",                  duration: 30, singleSided: false, moveType: .hold),
            SavedRoutineExercise(name: "Raised Forearms Child's Pose",   duration: 30, singleSided: false, moveType: .hold),
            SavedRoutineExercise(name: "Modified Pigeon Pose",          duration: 30, singleSided: true,  moveType: .hold),
            SavedRoutineExercise(name: "Supine Spinal Twist",           duration: 30, singleSided: true,  moveType: .hold),
        ],
        accentColorName: "indigo",
        systemImage: "moon.stars.fill",
        category: "Stretches",
        kind: .stretch
    )

    static let absWorkout = SavedWorkoutRoutine(
        name: "10 Minute Ab Workout",
        routineDescription: "A complete core circuit hitting every angle of your abs. 45 seconds on, 15 seconds rest. No equipment needed.",
        source: "Athlean-X",
        sourceURL: "https://youtu.be/i27K2ry9jEo?si=hetZqCfQWyWpgpXZ",
        exercises: [
            SavedRoutineExercise(name: "Crescent Tucks",         duration: 45, restDuration: 15, singleSided: false, restAfterEachSide: false, moveType: .move),
            SavedRoutineExercise(name: "Backward 7s",            duration: 45, restDuration: 15, singleSided: false, restAfterEachSide: false, moveType: .move),
            SavedRoutineExercise(name: "Swipers",                duration: 45, restDuration: 15, singleSided: false, restAfterEachSide: false, moveType: .move),
            SavedRoutineExercise(name: "Side Cycles",            duration: 45, restDuration: 15, singleSided: true,  restAfterEachSide: true,  moveType: .move),
            SavedRoutineExercise(name: "Mountain Hip Dips",      duration: 45, restDuration: 15, singleSided: false, restAfterEachSide: false, moveType: .move),
            SavedRoutineExercise(name: "Frog V-Ups",             duration: 45, restDuration: 15, singleSided: false, restAfterEachSide: false, moveType: .move),
            SavedRoutineExercise(name: "Side Scissor Crunches",  duration: 45, restDuration: 15, singleSided: true,  restAfterEachSide: true,  moveType: .move),
            SavedRoutineExercise(name: "Corpse Crunch",          duration: 45, restDuration: 0,  singleSided: false, restAfterEachSide: false, moveType: .move),
        ],
        accentColorName: "orange",
        systemImage: "figure.core.training",
        category: "Core",
        kind: .core
    )
}

// MARK: - Saved Routines List

extension SavedWorkoutRoutine {
    /// A copy with a fresh id (and fresh exercise ids), so it saves alongside the original
    /// rather than replacing it.
    func duplicated() -> SavedWorkoutRoutine {
        var copy = filed(name: name, category: category)
        copy.id = UUID()
        copy.exercises = exercises.map { exercise in
            var e = exercise
            e.id = UUID()
            return e
        }
        return copy
    }

    /// The same routine under a new name and folder (name and category are fixed at creation).
    func filed(name: String, category: String?) -> SavedWorkoutRoutine {
        SavedWorkoutRoutine(
            id: id,
            name: name,
            routineDescription: routineDescription,
            source: source,
            sourceURL: sourceURL,
            exercises: exercises,
            accentColorName: accentColorName,
            systemImage: systemImage,
            category: RoutineFolders.normalizedName(category),
            kind: kind
        )
    }
}

struct SavedRoutinesView: View {
    @State private var store = SavedRoutineStore.shared
    @State private var showingBuilder = false
    @State private var folderToRename: RoutineFolder?
    @State private var renameText = ""
    @State private var folderToDelete: RoutineFolder?
    @State private var showingImporter = false
    @State private var showImportAlert = false
    @State private var importAlertTitle = ""
    @State private var importAlertMessage = ""

    var body: some View {
        let grouped = RoutineFolders.folders(preloaded: PreloadedRoutines.all, user: store.routines)
        List {
            Section("Built-in") {
                ForEach(grouped.builtIn) { folder in
                    NavigationLink {
                        SavedFolderView(folderID: folder.id)
                    } label: {
                        FolderRow(folder: folder)
                    }
                }
            }

            Section {
                if grouped.user.isEmpty {
                    Text("Save a generated workout, a stretch routine, or one you build yourself and it shows up here, in the folder you choose.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(grouped.user) { folder in
                    NavigationLink {
                        SavedFolderView(folderID: folder.id)
                    } label: {
                        FolderRow(folder: folder)
                    }
                    .swipeActions(edge: .leading) {
                        if !folder.isUncategorized {
                            Button {
                                renameText = folder.name
                                folderToRename = folder
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
                .onDelete { offsets in
                    if let index = offsets.first { folderToDelete = grouped.user[index] }
                }
            } header: {
                Text("My Routines")
            }
        }
        .navigationTitle("Saved Routines")
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
#endif
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingImporter = true
                } label: {
                    Label("Import Routine", systemImage: "square.and.arrow.down")
                }
                Button {
                    showingBuilder = true
                } label: {
                    Label("Build Your Own", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingBuilder) {
            BuildYourOwnRoutineView()
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert(importAlertTitle, isPresented: $showImportAlert) {
            Button("OK") { }
        } message: {
            Text(importAlertMessage)
        }
        .alert("Rename Folder", isPresented: Binding(
            get: { folderToRename != nil },
            set: { if !$0 { folderToRename = nil } }
        )) {
            TextField("Folder name", text: $renameText)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                if let folder = folderToRename,
                   RoutineFolders.normalizedName(renameText) != nil {
                    store.renameCategory(from: folder.name, to: renameText)
                }
            }
        }
        .confirmationDialog(
            "Delete this folder?",
            isPresented: Binding(
                get: { folderToDelete != nil },
                set: { if !$0 { folderToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: folderToDelete
        ) { folder in
            Button("Delete \"\(folder.name)\" and \(folder.routines.count) routine\(folder.routines.count == 1 ? "" : "s")", role: .destructive) {
                store.deleteCategory(folder.name)
            }
        }
    }

    /// Reads a routine file (the current format, or an older exported workout) and files it in
    /// the folder named in the file, or Uncategorized. A routine can be moved afterwards from
    /// its folder's context menu.
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let fallbackName = url.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: url),
                  let routine = RoutineImport.parse(data, fallbackName: fallbackName.isEmpty ? "Imported Workout" : fallbackName) else {
                presentImportAlert(
                    title: "Couldn't Import",
                    message: "That file isn't a routine this app can read, or it has no exercises."
                )
                return
            }
            store.save(routine)
            let folder = RoutineFolders.normalizedName(routine.category) ?? RoutineFolders.uncategorizedName
            presentImportAlert(
                title: "Routine Imported",
                message: "\"\(routine.name)\" was added to \"\(folder)\"."
            )
        case .failure(let error):
            presentImportAlert(title: "Couldn't Import", message: error.localizedDescription)
        }
    }

    /// The file picker is still leaving when its completion runs, and an alert raised in that
    /// window can be dropped — so wait a beat.
    private func presentImportAlert(title: String, message: String) {
        importAlertTitle = title
        importAlertMessage = message
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            showImportAlert = true
        }
    }
}

private struct FolderRow: View {
    let folder: RoutineFolder

    private var tint: Color {
        switch folder.name {
        case "Stretches" where folder.isBuiltIn: return .teal
        case "Core" where folder.isBuiltIn: return .orange
        default: return folder.isUncategorized ? .gray : .indigo
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8)
                .fill(tint)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.white)
                        .font(.title3)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(folder.name)
                    .font(.body)
                    .fontWeight(.medium)
                Text("\(folder.routines.count) routine\(folder.routines.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// The routines in one folder. Looked up by id on every render rather than handed a snapshot,
/// so deleting or moving a routine updates the list — and a folder that empties out closes.
struct SavedFolderView: View {
    let folderID: String
    @State private var store = SavedRoutineStore.shared
    @State private var routineToMove: SavedWorkoutRoutine?
    @State private var exportDocument: RoutineDocument?
    @State private var exportFilename = "Routine"
    @State private var showingExporter = false
    @Environment(\.dismiss) private var dismiss

    private func export(_ routine: SavedWorkoutRoutine) {
        // Slashes would read as folders in the suggested filename.
        exportFilename = routine.name.replacingOccurrences(of: "/", with: "-")
        exportDocument = RoutineDocument(routine: routine)
        showingExporter = true
    }

    private var folder: RoutineFolder? {
        let grouped = RoutineFolders.folders(preloaded: PreloadedRoutines.all, user: store.routines)
        return (grouped.builtIn + grouped.user).first { $0.id == folderID }
    }

    private func isBuiltIn(_ routine: SavedWorkoutRoutine) -> Bool {
        PreloadedRoutines.all.contains { $0.id == routine.id }
    }

    var body: some View {
        let current = folder
        List {
            if let current, !current.routines.isEmpty {
                ForEach(current.routines) { routine in
                    NavigationLink(destination: SavedRoutineDetailView(routine: routine)) {
                        RoutineRow(routine: routine)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            export(routine)
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing) {
                        if !isBuiltIn(routine) {
                            Button(role: .destructive) {
                                store.delete(id: routine.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .contextMenu {
                        Button {
                            export(routine)
                        } label: {
                            Label("Export…", systemImage: "square.and.arrow.up")
                        }
                        if !isBuiltIn(routine) {
                            Button {
                                routineToMove = routine
                            } label: {
                                Label("Change Folder…", systemImage: "folder")
                            }
                            Button(role: .destructive) {
                                store.delete(id: routine.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } else {
                Text("No routines in this folder.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(current?.name ?? "Folder")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .onChange(of: current == nil) { _, isGone in
            if isGone { dismiss() }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                print("Routine export failed: \(error.localizedDescription)")
            }
            exportDocument = nil
        }
        .sheet(item: $routineToMove) { routine in
            SaveRoutinePromptView(
                title: "Change Folder",
                initialName: routine.name,
                initialCategory: routine.category ?? "",
                showsName: false,
                confirmLabel: "Move"
            ) { _, category in
                store.move(routine.id, toCategory: category)
            }
        }
    }
}

/// Free-text folder field with the existing folders offered as one-tap choices, so reusing a
/// folder doesn't depend on retyping its name exactly.
struct CategoryField: View {
    @Binding var text: String
    @State private var store = SavedRoutineStore.shared

    var body: some View {
        TextField("Folder (optional)", text: $text)
#if os(iOS)
            .textInputAutocapitalization(.words)
#endif
        let suggestions = RoutineFolders.suggestedNames(user: store.routines)
        OverflowScrollRow(items: suggestions) { name in
            let isSelected = RoutineFolders.key(text) == RoutineFolders.key(name)
            Button { text = name } label: {
                Text(name)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isSelected ? Color.blue : Color.gray.opacity(0.15))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

/// "Save as Routine" prompt: a name and an optional folder. Also reused, without the name
/// field, to move an existing routine to another folder.
struct SaveRoutinePromptView: View {
    let title: String
    var showsName = true
    var confirmLabel = "Save"
    let onSave: (String, String?) -> Void

    @State private var name: String
    @State private var category: String
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        initialName: String,
        initialCategory: String = "",
        showsName: Bool = true,
        confirmLabel: String = "Save",
        onSave: @escaping (String, String?) -> Void
    ) {
        self.title = title
        self.showsName = showsName
        self.confirmLabel = confirmLabel
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _category = State(initialValue: initialCategory)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                if showsName {
                    Section("Name") {
                        TextField("Routine Name", text: $name)
                    }
                }
                Section {
                    CategoryField(text: $category)
                } header: {
                    Text("Folder")
                } footer: {
                    Text("Leave blank to file it under Uncategorized.")
                }
            }
            .navigationTitle(title)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmLabel) {
                        onSave(trimmedName, RoutineFolders.normalizedName(category))
                        dismiss()
                    }
                    .disabled(showsName && trimmedName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct RoutineRow: View {
    let routine: SavedWorkoutRoutine

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8)
                .fill(routine.accentColor)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: routine.systemImage)
                        .foregroundStyle(.white)
                        .font(.title3)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.name)
                    .font(.body)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(routine.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(routine.exercises.count) exercises")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(routine.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Routine Detail

struct SavedRoutineDetailView: View {
    let routine: SavedWorkoutRoutine
    @State private var showingPlayer = false
    @State private var selectedIntention: WorkoutIntention = .generalFitness

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(routine.source)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Text(routine.name)
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(routine.formattedDuration)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(routine.accentColor)
                            Text("total")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !routine.routineDescription.isEmpty {
                        Text(routine.routineDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !routine.sourceURL.isEmpty, let url = URL(string: routine.sourceURL) {
                        Link(destination: url) {
                            Label("Watch on YouTube", systemImage: "play.rectangle.fill")
                                .font(.caption)
                                .foregroundStyle(routine.accentColor)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding()
                .background(.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Exercise list
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exercises")
                        .font(.title3)
                        .fontWeight(.semibold)

                    ForEach(Array(routine.exercises.enumerated()), id: \.offset) { index, ex in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 22, alignment: .trailing)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.name)
                                    .font(.subheadline)
                                HStack(spacing: 6) {
                                    Text(ex.moveType.rawValue)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(ex.moveType == .hold ? Color.teal.opacity(0.15) : Color.orange.opacity(0.15))
                                        .foregroundStyle(ex.moveType == .hold ? .teal : .orange)
                                        .clipShape(Capsule())
                                    if ex.singleSided {
                                        Text("Each side")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(ex.duration)s")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(routine.accentColor)
                                if ex.restDuration > 0 {
                                    Text("+ \(ex.restDuration)s rest")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(.gray.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                // Intention — frames the HR-zone targets and recap for this session, same as
                // the generator's own Intention picker (WorkoutGeneratorView.swift). Stretching
                // has no HR-zone target to frame, so stretch routines skip it.
                if !routine.isFlexibilitySession {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Intention")
                            .font(.title3)
                            .fontWeight(.semibold)
                        OverflowScrollRow(items: WorkoutIntention.allCases) { intent in
                            Button { selectedIntention = intent } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: intent.icon)
                                        .font(.subheadline)
                                    Text(intent.rawValue)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(selectedIntention == intent ? intent.bannerColor : Color.gray.opacity(0.1))
                                .foregroundStyle(selectedIntention == intent ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Start button
                Button {
                    showingPlayer = true
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Routine")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(routine.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .navigationTitle(routine.name)
#if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .sheet(isPresented: $showingPlayer) {
            SavedRoutinePlayerView(routine: routine, intention: selectedIntention)
        }
    }
}

// MARK: - Player Step Model

private struct PlayerStep: Identifiable {
    let id = UUID()
    let label: String
    let sideLabel: String?
    let duration: Int
    let isRest: Bool
    let accentColor: Color
}

// MARK: - Saved Routine Player

struct SavedRoutinePlayerView: View {
    let routine: SavedWorkoutRoutine
    var intention: WorkoutIntention = .generalFitness

    @State private var steps: [PlayerStep] = []
    @State private var currentIndex = 0
    @State private var timeRemaining = 0
    @State private var isPlaying = false
    @State private var isPaused = false
    @State private var timer: Timer?
    @State private var showingRecap = false
    // Recap stats — mirrors WorkoutPlayerView's own tracking so saved/built routines get the
    // same rich WorkoutRecapView instead of a bare name-and-duration screen.
    @State private var totalExerciseTime = 0
    @State private var totalRestTime = 0
    @State private var completedStepNames: [String] = []
    @State private var peakHeartRate: Double = 0
    @State private var heartRateSamples: [Double] = []
    @Environment(\.dismiss) private var dismiss
    @StateObject private var connectivityManager = WorkoutConnectivityManager.shared
    @StateObject private var videoManager = VideoManager.shared

#if canImport(AVFoundation)
    @State private var audioEngine: AVAudioEngine?
    @State private var playerNode: AVAudioPlayerNode?
    @State private var avPlayer: AVPlayer?
    @State private var playerEndObserver: Any?
#endif

    private var currentStep: PlayerStep? {
        guard currentIndex < steps.count else { return nil }
        return steps[currentIndex]
    }

    private var timerProgress: Double {
        guard let step = currentStep, step.duration > 0 else { return 1 }
        return Double(timeRemaining) / Double(step.duration)
    }

    private var videoURL: URL? {
        guard let step = currentStep, !step.isRest else { return nil }
        return VideoManager.shared.url(for: step.label)
    }

    private var nextUpText: String {
        let nextIndex = currentIndex + 1
        guard nextIndex < steps.count else { return "End of routine" }
        let step = steps[nextIndex]
        return step.isRest ? "Rest" : step.label
    }

    private var averageHeartRate: Double {
        heartRateSamples.isEmpty ? 0 : heartRateSamples.reduce(0, +) / Double(heartRateSamples.count)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        Spacer(minLength: 8)

                        // Video area
                        if let mode = VideoMode(rawValue: videoManager.videoMode), mode != .none {
#if canImport(AVFoundation)
                            if let player = avPlayer {
                                VideoPlayer(player: player)
                                    .frame(height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .padding(.horizontal)
                            } else if let step = currentStep, !step.isRest {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.gray.opacity(0.08))
                                    VStack(spacing: 6) {
                                        Image(systemName: "video.slash")
                                            .font(.title)
                                            .foregroundStyle(.secondary)
                                        Text("No Video Available")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(height: 180)
                                .padding(.horizontal)
                            }
#endif
                        }

                        // Step name
                        VStack(spacing: 6) {
                            if let step = currentStep {
                                if let side = step.sideLabel {
                                    Text(side)
                                        .font(.subheadline)
                                        .foregroundStyle(routine.accentColor)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 4)
                                        .background(routine.accentColor.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                                Text(step.label)
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            } else {
                                Text("Complete!")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.green)
                            }
                        }

                        // Timer ring
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.15), lineWidth: 10)
                            Circle()
                                .trim(from: 0, to: timerProgress)
                                .stroke(
                                    currentStep?.isRest == true ? Color.blue : routine.accentColor,
                                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 1), value: timeRemaining)
                            Text(isPlaying ? "\(timeRemaining)" : "\(currentStep?.duration ?? 0)")
                                .font(.system(size: 64, weight: .bold, design: .monospaced))
                                .foregroundStyle(timeRemaining <= 3 && isPlaying ? .red : .primary)
                        }
                        .frame(width: 180, height: 180)

                        // Progress and Next up
                        if !steps.isEmpty {
                            Text("Step \(min(currentIndex + 1, steps.count)) of \(steps.count)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if isPlaying && currentIndex < steps.count {
                            HStack(spacing: 4) {
                                Text("Next:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(nextUpText)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(nextUpText == "Rest" ? .blue : (nextUpText == "End of routine" ? .green : .primary))
                            }
                        }

                        // Live workout stats (exercise time, HR zone, nutrient burn) and the
                        // Apple Watch metrics panel — the same ones generated workouts show.
                        if isPlaying {
                            #if os(iOS)
                            WorkoutLiveStatsView(
                                exerciseTime: totalExerciseTime,
                                heartRate: connectivityManager.heartRate,
                                hasWatchData: connectivityManager.isWatchConnected && connectivityManager.heartRate > 0,
                                intention: intention,
                                zoneThresholds: connectivityManager.watchZoneThresholds
                            )
                            .padding(.top, 4)
                            #else
                            WorkoutLiveStatsView(exerciseTime: totalExerciseTime, heartRate: 0, hasWatchData: false, intention: intention)
                                .padding(.top, 4)
                            #endif
                        }

                        #if os(iOS)
                        if isPlaying && connectivityManager.isWatchConnected {
                            HealthMetricsView(connectivityManager: connectivityManager)
                                .padding(.horizontal)
                                .padding(.top, 4)
                        }
                        #endif

                        Spacer(minLength: 8)
                    }
                }

                // Controls
                VStack(spacing: 6) {
                    HStack(spacing: 40) {
                        if !isPlaying {
                            Button { startRoutine() } label: {
                                controlCircle(icon: "play.fill", label: "Start", color: routine.accentColor)
                            }
                        } else {
                            Button { togglePause() } label: {
                                controlCircle(
                                    icon: isPaused ? "play.fill" : "pause.fill",
                                    label: isPaused ? "Resume" : "Pause",
                                    color: .blue
                                )
                            }
                            Button { skipStep() } label: {
                                controlCircle(icon: "forward.fill", label: "Skip", color: .orange)
                            }
                        }
                    }
#if os(iOS)
                    if !isPlaying {
                        let msg = connectivityManager.isWatchReachable
                            ? "You can also start from your Apple Watch"
                            : connectivityManager.isWatchConnected
                                ? "Watch Connected"
                                : "Looking for Watch…"
                        Label(msg, systemImage: "applewatch")
                            .font(.caption)
                            .foregroundStyle(connectivityManager.isWatchReachable ? .secondary : .tertiary)
                    }
#endif
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(.thinMaterial)
                .shadow(radius: 2)
                .padding(.horizontal)
            }
            .navigationTitle("Workout")
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { stopRoutine(); dismiss() }
                }
            }
#else
            .toolbar {
                ToolbarItem { Button("Done") { stopRoutine(); dismiss() } }
            }
#endif
        }
        .onAppear {
            buildSteps()
            if let first = steps.first { timeRemaining = first.duration }
            setupAudio()
            prepareWatchHandoff()
            prepareVideoForCurrentStep(autoplay: false)
        }
        .onDisappear { stopRoutine() }
#if os(iOS)
        .onChange(of: connectivityManager.watchRequestedStart) { _, requested in
            if requested {
                connectivityManager.watchRequestedStart = false
                if !isPlaying { startRoutine() }
            }
        }
        .onChange(of: connectivityManager.watchRequestedStop) { _, requested in
            if requested {
                connectivityManager.watchRequestedStop = false
                if isPlaying { stopRoutine(); dismiss() }
            }
        }
        // The Apple Watch tapped Pause/Resume — mirror it here so both devices agree
        .onChange(of: connectivityManager.watchRequestedPause) { _, requested in
            if requested {
                connectivityManager.watchRequestedPause = false
                if isPlaying { togglePause() }
            }
        }
        // The Apple Watch tapped Skip — advance one step on the iPhone too
        .onChange(of: connectivityManager.watchRequestedSkip) { _, requested in
            if requested {
                connectivityManager.watchRequestedSkip = false
                if isPlaying { skipStep() }
            }
        }
#endif
        .sheet(isPresented: $showingRecap) {
            WorkoutRecapView(
                completedExercises: completedStepNames,
                totalExerciseTime: totalExerciseTime,
                totalRestTime: totalRestTime,
                totalCalories: {
                    #if os(iOS)
                    return connectivityManager.activeCalories
                    #else
                    return 0
                    #endif
                }(),
                peakHeartRate: peakHeartRate,
                averageHeartRate: averageHeartRate,
                hrZoneDurations: {
                    #if os(iOS)
                    return connectivityManager.completedZoneDurations
                    #else
                    return []
                    #endif
                }(),
                // Stretching has no Intention, so the recap leaves out the zone-alignment score.
                intention: routine.isFlexibilitySession ? nil : intention,
                // Core-only routines skip the alignment score, as live Core workouts do.
                selectedFocusAreas: routine.kind == .core ? ["Core"] : [],
                onDismiss: {
                    showingRecap = false
                    dismiss()
                }
            )
        }
    }

    private func buildSteps() {
        var result: [PlayerStep] = []
        for ex in routine.exercises {
            if ex.singleSided {
                result.append(PlayerStep(label: ex.name, sideLabel: "Left Side",  duration: ex.duration, isRest: false, accentColor: routine.accentColor))
                if ex.restAfterEachSide && ex.restDuration > 0 {
                    result.append(PlayerStep(label: "Rest", sideLabel: nil, duration: ex.restDuration, isRest: true, accentColor: routine.accentColor))
                }
                result.append(PlayerStep(label: ex.name, sideLabel: "Right Side", duration: ex.duration, isRest: false, accentColor: routine.accentColor))
                if ex.restDuration > 0 {
                    result.append(PlayerStep(label: "Rest", sideLabel: nil, duration: ex.restDuration, isRest: true, accentColor: routine.accentColor))
                }
            } else {
                result.append(PlayerStep(label: ex.name, sideLabel: nil, duration: ex.duration, isRest: false, accentColor: routine.accentColor))
                if ex.restDuration > 0 {
                    result.append(PlayerStep(label: "Rest", sideLabel: nil, duration: ex.restDuration, isRest: true, accentColor: routine.accentColor))
                }
            }
        }
        steps = result
    }

    private func startRoutine() {
        guard !steps.isEmpty else { return }
        isPlaying = true
        isPaused = false
        currentIndex = 0
        timeRemaining = steps[0].duration
        setIdleTimer(disabled: true)
        scheduleTimer()
        playBeep(type: .start)
        sendWorkoutStateToWatch()
        launchWatchWorkoutSession()
        prepareVideoForCurrentStep(autoplay: true)
    }

    private func togglePause() {
        isPaused.toggle()
        if isPaused {
            timer?.invalidate()
            timer = nil
#if canImport(AVFoundation)
            avPlayer?.pause()
#endif
        } else {
            scheduleTimer()
#if canImport(AVFoundation)
            avPlayer?.play()
#endif
        }
        sendWorkoutStateToWatch()
        sendControlToWatch(isPaused ? .workoutPaused : .workoutResumed)
    }

    private func skipStep() {
        advance()
    }

    private func stopRoutine() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
        setIdleTimer(disabled: false)
        sendControlToWatch(.workoutStopped)
#if canImport(AVFoundation)
        avPlayer?.pause()
        avPlayer = nil
        if let obs = playerEndObserver {
            NotificationCenter.default.removeObserver(obs)
            playerEndObserver = nil
        }
#endif
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            tick()
        }
    }

    private func tick() {
        guard isPlaying && !isPaused else { return }
        if timeRemaining > 1 {
            timeRemaining -= 1

            if currentStep?.isRest == true {
                totalRestTime += 1
            } else {
                totalExerciseTime += 1
            }

#if os(iOS)
            let hr = connectivityManager.heartRate
            if hr > 0 {
                heartRateSamples.append(hr)
                if hr > peakHeartRate { peakHeartRate = hr }
            }
#endif

            let t = timeRemaining
            connectivityManager.sendTimerUpdate(timeRemaining: t)
            if timeRemaining == 3 { playBeep(type: .warning) }
        } else {
            advance()
        }
    }

    private func advance() {
        playBeep(type: .end)
        if let step = currentStep, !step.isRest {
            completedStepNames.append(step.label)
        }
        let next = currentIndex + 1
        if next < steps.count {
            currentIndex = next
            timeRemaining = steps[next].duration
            sendWorkoutStateToWatch()
            prepareVideoForCurrentStep(autoplay: true)
        } else {
            timer?.invalidate()
            timer = nil
            isPlaying = false
            setIdleTimer(disabled: false)
            playBeep(type: .complete)
#if os(iOS)
            connectivityManager.sendWorkoutCompleted(
                count: completedStepNames.count,
                totalSeconds: totalExerciseTime + totalRestTime,
                label: routine.name
            )
#endif
            sendControlToWatch(.workoutStopped)
#if canImport(AVFoundation)
            avPlayer?.pause()
            avPlayer = nil
            if let obs = playerEndObserver {
                NotificationCenter.default.removeObserver(obs)
                playerEndObserver = nil
            }
#endif
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingRecap = true
            }
        }
    }

    private func prepareVideoForCurrentStep(autoplay: Bool) {
#if canImport(AVFoundation)
        if let obs = playerEndObserver {
            NotificationCenter.default.removeObserver(obs)
            playerEndObserver = nil
        }
        guard let step = currentStep, !step.isRest,
              let url = VideoManager.shared.url(for: step.label) else {
            avPlayer?.pause()
            avPlayer = nil
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let item = AVPlayerItem(url: url)
            DispatchQueue.main.async {
                let player: AVPlayer
                if let existing = self.avPlayer {
                    existing.replaceCurrentItem(with: item)
                    player = existing
                } else {
                    player = AVPlayer(playerItem: item)
                    player.isMuted = true
                    player.actionAtItemEnd = .none
                }
                self.playerEndObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { _ in
                    player.seek(to: .zero)
                    player.play()
                }
                self.avPlayer = player
                if autoplay { player.play() }
            }
        }
#endif
    }

    private func setIdleTimer(disabled: Bool) {
#if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = disabled
#endif
    }

    @ViewBuilder
    private func controlCircle(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 28))
            Text(label).font(.caption)
        }
        .frame(width: 80, height: 80)
        .background(color)
        .foregroundStyle(.white)
        .clipShape(Circle())
    }

    // MARK: - Audio

    private func setupAudio() {
#if canImport(AVFoundation)
    #if os(iOS) || os(tvOS) || os(visionOS)
        if audioEngine == nil {
            let engine = AVAudioEngine()
            let output = engine.outputNode
            let hwFormat = output.outputFormat(forBus: 0)
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: hwFormat)
            engine.connect(engine.mainMixerNode, to: output, format: hwFormat)
            engine.mainMixerNode.outputVolume = 1.0
            engine.mainMixerNode.volume = 1.0
            audioEngine = engine
            playerNode = node
            do { try engine.start() } catch { }
        }
    #endif
#endif
    }

    private func playBeep(type: FeedbackEvent) {
        triggerHaptic(for: type)
#if os(macOS)
        switch type {
        case .start:
            NSSound.beep()
        case .warning:
            NSSound.beep(); NSSound.beep()
        case .end:
            NSSound.beep(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { NSSound.beep() }
        case .complete:
            NSSound.beep()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSSound.beep() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { NSSound.beep() }
        case .enterActive, .enterCoolDown:
            // Saved routines have no warm-up/cool-down phase of their own to transition into.
            break
        }
        return
#endif
#if canImport(AVFoundation)
    #if os(iOS) || os(tvOS) || os(visionOS)
        DispatchQueue.global(qos: .utility).async {
            let audioSession = AVAudioSession.sharedInstance()
            _ = try? audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            _ = try? audioSession.setActive(true, options: [])
        }

        if audioEngine == nil || playerNode == nil { setupAudio() }
        guard let engine = audioEngine else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let node: AVAudioPlayerNode
            if let existing = self.playerNode {
                node = existing
            } else {
                let newNode = AVAudioPlayerNode()
                engine.attach(newNode)
                let hwFormat = engine.outputNode.outputFormat(forBus: 0)
                engine.connect(newNode, to: engine.mainMixerNode, format: hwFormat)
                self.playerNode = newNode
                node = newNode
            }

            if !engine.isRunning { try? engine.start() }
            engine.mainMixerNode.outputVolume = 1.0
            engine.mainMixerNode.volume = 1.0

            let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
            let sampleRate = mixerFormat.sampleRate

            let (frequency, duration): (Double, Double)
            switch type {
            case .start:    (frequency, duration) = (880, 0.12)
            case .warning:  (frequency, duration) = (1400, 0.10)
            case .end:      (frequency, duration) = (523.25, 0.22)
            case .complete: (frequency, duration) = (659.25, 0.18)
            // Saved routines never emit these — no warm-up/cool-down phase here — but the
            // switch must stay exhaustive since FeedbackEvent is shared with the main player.
            case .enterActive, .enterCoolDown: (frequency, duration) = (880, 0.12)
            }

            let frames = AVAudioFrameCount(sampleRate * duration)
            guard let buf = AVAudioPCMBuffer(pcmFormat: mixerFormat, frameCapacity: frames) else { return }
            buf.frameLength = frames

            let total = Int(frames)
            let channelCount = Int(mixerFormat.channelCount)
            for ch in 0..<channelCount {
                if let data = buf.floatChannelData?[ch] {
                    for i in 0..<total {
                        let t = Double(i) / sampleRate
                        data[i] = Float(sin(2.0 * Double.pi * frequency * t) * 0.6)
                    }
                }
            }

            DispatchQueue.main.async {
                node.scheduleBuffer(buf, completionHandler: nil)
                if !node.isPlaying { node.play() }
            }
        }
    #endif
#endif
    }

    private func triggerHaptic(for event: FeedbackEvent) {
#if os(iOS)
    #if canImport(UIKit)
        switch event {
        case .start:
            let g = UIImpactFeedbackGenerator(style: .medium)
            g.prepare(); g.impactOccurred()
        case .warning:
            let g = UIImpactFeedbackGenerator(style: .rigid)
            g.prepare(); g.impactOccurred(intensity: 1.0)
        case .end:
            let g = UINotificationFeedbackGenerator()
            g.prepare(); g.notificationOccurred(.success)
        case .complete:
            let g = UINotificationFeedbackGenerator()
            g.prepare(); g.notificationOccurred(.success)
        case .enterActive:
            let g = UIImpactFeedbackGenerator(style: .heavy)
            g.prepare(); g.impactOccurred()
        case .enterCoolDown:
            let g = UIImpactFeedbackGenerator(style: .soft)
            g.prepare(); g.impactOccurred()
        }
    #endif
#endif
    }

    // MARK: - Watch Connectivity

    private func prepareWatchHandoff() {
#if os(iOS)
        guard !isPlaying else { return }
        connectivityManager.watchRequestedStart = false
        connectivityManager.sendPrepareToStart(activityTypeRaw: declaredActivityTypeRaw)
        launchWatchWorkoutSession()
#endif
    }

    /// What the watch should record this session as, sent with the ready signal and every state
    /// so it doesn't hinge on the `startWatchApp` handoff arriving first.
    private var declaredActivityTypeRaw: UInt? {
#if canImport(HealthKit)
        routine.resolvedActivityType(intention: intention).rawValue
#else
        nil
#endif
    }

    private func launchWatchWorkoutSession() {
#if canImport(HealthKit)
#if os(iOS)
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = routine.resolvedActivityType(intention: intention)
        configuration.locationType = .indoor
        store.startWatchApp(with: configuration) { success, error in
            if let error = error {
                print("Failed to launch watch app: \(error.localizedDescription)")
            }
        }
#endif
#endif
    }

    private func sendWorkoutStateToWatch() {
#if os(iOS)
        let step = currentIndex < steps.count ? steps[currentIndex] : nil
        let nextStep = (currentIndex + 1) < steps.count ? steps[currentIndex + 1] : nil
        let state = WorkoutState(
            currentExerciseName: step?.label ?? "Complete",
            currentIndex: currentIndex,
            totalExercises: steps.count,
            timeRemaining: timeRemaining,
            isRest: step?.isRest ?? false,
            nextExerciseName: nextStep?.label,
            isPlaying: isPlaying,
            isPaused: isPaused,
            sideLabel: step?.sideLabel,
            activityTypeRaw: declaredActivityTypeRaw
        )
        connectivityManager.sendWorkoutState(state)
#endif
    }

    private func sendControlToWatch(_ control: ControlMessage) {
#if os(iOS)
        connectivityManager.sendControlMessage(control)
#endif
    }
}
