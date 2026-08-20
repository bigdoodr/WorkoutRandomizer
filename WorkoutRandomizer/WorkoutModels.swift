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
    let blockDurations: [Int]   // work seconds per block; rest = same
}

enum WorkoutIntention: String, CaseIterable, Identifiable {
    case generalFitness = "General Fitness"
    case fatBurn = "Fat Burn"
    case cardioEndurance = "Cardio Endurance"
    case strengthPower = "Strength / Power"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .generalFitness: return "star"
        case .fatBurn: return "flame"
        case .cardioEndurance: return "heart"
        case .strengthPower: return "bolt"
        }
    }

    var bannerColor: Color {
        switch self {
        case .generalFitness: return .green
        case .fatBurn: return .orange
        case .cardioEndurance: return .red
        case .strengthPower: return .blue
        }
    }

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
        case (.strengthPower, "Zone 5"): return "Explosive power output. Great for HIIT."
        case (.generalFitness, "Zone 1"): return "Good for warm-up or cool-down."
        case (.generalFitness, "Zone 2"): return "Steady-state cardio zone."
        case (.generalFitness, "Zone 3"): return "Moderate effort. Good overall fitness."
        case (.generalFitness, "Zone 4"): return "High intensity. Improving fitness quickly."
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

struct WorkoutItem {
    let exercise: Exercise
    let isRest: Bool
    let duration: Int
}

// MARK: - Import/Export Models
struct ExportableExercise: Codable, Identifiable {
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

struct WorkoutDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var exercises: [ExportableExercise]
    
    init(exercises: [ExportableExercise]) {
        self.exercises = exercises
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        exercises = try JSONDecoder().decode([ExportableExercise].self, from: data)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(exercises)
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Array Unique Extension
extension Array where Element: Hashable {
    func unique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
