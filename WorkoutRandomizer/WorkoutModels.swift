//  WorkoutModels.swift
//  Bodyweight WorkoutRandomizer
//
//  Core value types, the custom-exercise store, and import/export models.
//  Extracted from WorkoutRandomizer.swift — no behaviour change.

import SwiftUI
internal import UniformTypeIdentifiers
import Observation
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(AVKit)
import AVKit
#endif
#if canImport(HealthKit)
import HealthKit
#endif
#if os(macOS)
import AppKit
#endif

struct Exercise {
    let name: String
    let videoPath: String?
    let equipment: [String]
    var singleSided: Bool = false
    var isMovement: Bool = false
    /// Workout focus areas this exercise is relevant to beyond its own category. Only
    /// populated for warm-up and cool-down stretches; empty means "suits any focus".
    var relatedFocusAreas: [String] = []
    /// Non-nil for warm-up and cool-down slots. These run at their own fixed duration and sit
    /// *outside* the timer style's phase counting — see `WorkoutTiming.exercisePosition`.
    var preparationDuration: Int? = nil

    /// True for warm-up and cool-down slots, including the rests between them.
    var isPreparation: Bool { preparationDuration != nil }
}

enum TimerStyle: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case pyramid = "Pyramid"
    case blocks = "Repeating Blocks"
    /// Each round repeats the previous one and appends a new exercise: [A], [A B], [A B C]…
    case addOn = "Add-On"
    /// Builds up like Add-On, then peels an exercise off each round until only the first
    /// exercise remains for the final round.
    case addOnTakeAway = "Add-On + Take Away"
    var id: String { rawValue }

    /// Ladder styles derive their own sequence rather than filling a flat list.
    var isLadder: Bool { self == .addOn || self == .addOnTakeAway }

    var shortLabel: String {
        switch self {
        case .standard: return "Standard"
        case .pyramid: return "Pyramid"
        case .blocks: return "Blocks"
        case .addOn: return "Add-On"
        case .addOnTakeAway: return "Add-On +/-"
        }
    }
}

struct RepeatingBlocksConfig: Equatable {
    let exercisesPerBlock: Int
    let blockDurations: [Int]   // work seconds per block
    /// Rest after the last exercise of a full cycle, before the next cycle starts — distinct
    /// from the short rest between exercises within a cycle. Nil falls back to the same
    /// derived-from-work rest every other slot uses, matching behavior before this existed.
    var cycleRestSeconds: Int? = nil
}

nonisolated enum WorkoutIntention: String, CaseIterable, Identifiable {
    case generalFitness = "General Fitness"
    case fatBurn = "Fat Burn"
    case cardioEndurance = "Cardio Endurance"
    case strengthPower = "Strength / Power"
    /// Short, near-maximal work with incomplete rest. Doesn't change which exercises are
    /// picked — the "Cardio" focus area / quick filter still controls that — this only frames
    /// the HR-zone targets and tips around anaerobic intervals rather than sustained effort.
    case hiit = "HIIT"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .generalFitness: return "star"
        case .fatBurn: return "flame"
        case .cardioEndurance: return "heart"
        case .strengthPower: return "bolt"
        case .hiit: return "bolt.heart"
        }
    }

    var bannerColor: Color {
        switch self {
        case .generalFitness: return .green
        case .fatBurn: return .orange
        case .cardioEndurance: return .red
        case .strengthPower: return .blue
        case .hiit: return .pink
        }
    }

#if canImport(HealthKit)
    /// What a session is logged as in Apple Health when its content doesn't point at one
    /// specific activity (Core-only, Cardio-only, stretch). Shared by live workouts and saved
    /// routines so the two can't drift apart.
    var healthKitActivityType: HKWorkoutActivityType {
        switch self {
        case .strengthPower: return .functionalStrengthTraining
        case .cardioEndurance: return .mixedCardio
        case .generalFitness, .fatBurn, .hiit: return .highIntensityIntervalTraining
        }
    }
#endif

    func tip(for zone: String) -> String {
        switch (self, zone) {
        case (.fatBurn, "Zone 1"): return "Low intensity — light fat burn."
        case (.fatBurn, "Zone 2"): return "Optimal fat-oxidation zone."
        case (.fatBurn, "Zone 3"): return "Mixed fuel — fat + carbs."
        case (.fatBurn, "Zone 4"): return "Carb-dominant. EPOC effect boosts fat loss post-workout."
        case (.fatBurn, "Zone 5"): return "Max effort — significant afterburn effect."
        case (.cardioEndurance, "Zone 1"): return "Recovery pace. Push to Zone 2+ for gains."
        case (.cardioEndurance, "Zone 2"): return "Builds aerobic base efficiently."
        case (.cardioEndurance, "Zone 3"): return "Threshold training. Good for endurance."
        case (.cardioEndurance, "Zone 4"): return "Increases VO₂ max. Key zone for endurance gains."
        case (.cardioEndurance, "Zone 5"): return "Peak capacity. Use for short intervals."
        case (.strengthPower, "Zone 1"): return "Active recovery between sets."
        case (.strengthPower, "Zone 2"): return "Steady circuit pace."
        case (.strengthPower, "Zone 3"): return "Good for circuit-style strength work."
        case (.strengthPower, "Zone 4"): return "Power endurance territory."
        case (.strengthPower, "Zone 5"): return "Explosive power output."
        case (.generalFitness, "Zone 1"): return "Good for warm-up or cool-down."
        case (.generalFitness, "Zone 2"): return "Steady-state cardio zone."
        case (.generalFitness, "Zone 3"): return "Moderate effort. Good overall fitness."
        case (.generalFitness, "Zone 4"): return "High intensity. Improving fitness quickly."
        case (.hiit, "Zone 1"): return "Too easy for HIIT — this should be your rest interval, not your work interval."
        case (.hiit, "Zone 2"): return "Still warming up. Push harder on the next work interval."
        case (.hiit, "Zone 3"): return "Getting there — one more gear for a true HIIT effort."
        case (.hiit, "Zone 4"): return "This is the target zone for HIIT work intervals."
        case (.hiit, "Zone 5"): return "Max anaerobic effort — exactly what a short HIIT interval should feel like."
        default: return "Max effort. Use sparingly."
        }
    }
}

struct UserExercise: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var focusArea: String
    var difficulty: String
}

@MainActor
@Observable
final class CustomExerciseStore {
    static let shared = CustomExerciseStore()
    private static let storageKey = "customExercises_v1"

    var exercises: [UserExercise] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([UserExercise].self, from: data) {
            exercises = decoded
        }
    }

    func add(_ exercise: UserExercise) {
        exercises.append(exercise)
        persist()
    }

    func remove(at offsets: IndexSet) {
        exercises.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(exercises) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

/// Names of exercises/stretches the user has starred, keyed by exercise name (matches how
/// `Exercise` is looked up elsewhere — there's no stable id, just the catalog name).
@MainActor
@Observable
final class FavoritesStore {
    static let shared = FavoritesStore()
    private static let storageKey = "favoriteExerciseNames_v1"

    private(set) var names: Set<String> = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            names = decoded
        }
    }

    func isFavorite(_ name: String) -> Bool { names.contains(name) }

    func toggle(_ name: String) {
        if names.contains(name) {
            names.remove(name)
        } else {
            names.insert(name)
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(names) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

struct WorkoutItem {
    let exercise: Exercise
    let isRest: Bool
    let duration: Int
}

// MARK: - Import/Export Models

/// The shape workouts were exported in before routines had their own file format: a flat list
/// of exercises with one duration and one rest each. Only read now, so files from older
/// versions still import.
nonisolated struct ExportableExercise: Codable, Identifiable {
    let id: String
    let name: String
    let isTimeBased: Bool
    let exerciseDuration: Int
    let restDuration: Int
    let sets: Int
    
    init(id: String = UUID().uuidString, name: String, isTimeBased: Bool, exerciseDuration: Int, restDuration: Int, sets: Int) {
        self.id = id
        self.name = name
        self.isTimeBased = isTimeBased
        self.exerciseDuration = exerciseDuration
        self.restDuration = restDuration
        self.sets = sets
    }
}

/// A whole saved routine on disk — every exercise's own duration, rest, sides and Hold/Move,
/// plus its folder, color and icon — so exporting and re-importing is lossless. `format` and
/// `version` let the importer tell this apart from other JSON and evolve the file later.
nonisolated struct RoutineExportFile: Codable {
    static let formatName = "WorkoutRandomizerRoutine"

    var format: String = RoutineExportFile.formatName
    var version: Int = 1
    var routine: SavedWorkoutRoutine
}

enum RoutineImport {
    /// Reads either file shape and returns a routine ready to save, or nil when the data is
    /// neither (or has nothing to play). Imported routines always get a fresh id, so importing
    /// a file you exported yourself adds a copy instead of colliding with the original.
    static func parse(_ data: Data, fallbackName: String) -> SavedWorkoutRoutine? {
        let decoder = JSONDecoder()
        if let file = try? decoder.decode(RoutineExportFile.self, from: data),
           file.format == RoutineExportFile.formatName {
            return sanitized(file.routine.duplicated())
        }
        if let legacy = try? decoder.decode([ExportableExercise].self, from: data) {
            return fromLegacy(legacy, name: fallbackName)
        }
        return nil
    }

    /// Old files list every slot including the rests between them, and also carry each
    /// exercise's following rest — so the "Rest" entries are redundant and skipped. The last
    /// exercise's rest was only ever a configured fallback, not a real rest, so it's dropped.
    static func fromLegacy(_ entries: [ExportableExercise], name: String) -> SavedWorkoutRoutine? {
        let work = entries.filter { $0.name != "Rest" }
        guard !work.isEmpty else { return nil }
        let exercises = work.enumerated().map { index, entry in
            SavedRoutineExercise(
                name: entry.name,
                duration: entry.exerciseDuration,
                restDuration: index < work.count - 1 ? entry.restDuration : 0,
                singleSided: false,
                restAfterEachSide: false,
                moveType: .move
            )
        }
        let routine = SavedWorkoutRoutine(
            name: name,
            routineDescription: "",
            source: "Imported",
            sourceURL: "",
            exercises: exercises,
            accentColorName: "purple",
            systemImage: "dumbbell.fill"
        )
        return sanitized(routine)
    }

    /// Files come from outside the app, so keep timings in a range the player can run.
    private static func sanitized(_ routine: SavedWorkoutRoutine) -> SavedWorkoutRoutine? {
        guard !routine.exercises.isEmpty else { return nil }
        var cleaned = routine
        cleaned.exercises = routine.exercises.map { exercise in
            var e = exercise
            e.duration = min(max(e.duration, 1), 3600)
            e.restDuration = min(max(e.restDuration, 0), 3600)
            return e
        }
        return cleaned
    }
}

/// Export-only wrapper handed to `fileExporter`.
struct RoutineDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var routine: SavedWorkoutRoutine

    init(routine: SavedWorkoutRoutine) {
        self.routine = routine
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let parsed = RoutineImport.parse(data, fallbackName: "Imported Workout") else {
            throw CocoaError(.fileReadCorruptFile)
        }
        routine = parsed
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(RoutineExportFile(routine: routine))
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try encodedData())
    }
}

// MARK: - Array Unique Extension
extension Array where Element: Hashable {
    func unique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
