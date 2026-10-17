//
//  WorkoutRandomizerTests.swift
//  WorkoutRandomizerTests
//
//  Created by Casey Scruggs on 12/19/25.
//

import Foundation
import HealthKit
import Testing
@testable import WorkoutRandomizer

struct WorkoutRandomizerTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}

@MainActor
struct RoutineFolderTests {

    private func routine(_ name: String, category: String? = nil) -> SavedWorkoutRoutine {
        SavedWorkoutRoutine(
            name: name,
            routineDescription: "",
            source: "You",
            sourceURL: "",
            exercises: [SavedRoutineExercise(name: "Squat", duration: 30)],
            accentColorName: "purple",
            systemImage: "star.fill",
            category: category
        )
    }

    @Test func keyIgnoresCaseAndSpacing() {
        #expect(RoutineFolders.key("  Core ") == RoutineFolders.key("core"))
        #expect(RoutineFolders.key("Man  of   Steel") == RoutineFolders.key("man of steel"))
    }

    @Test func blankAndUncategorizedNormalizeToNil() {
        #expect(RoutineFolders.normalizedName(nil) == nil)
        #expect(RoutineFolders.normalizedName("   ") == nil)
        #expect(RoutineFolders.normalizedName("uncategorized") == nil)
        #expect(RoutineFolders.normalizedName("  Push   Day ") == "Push Day")
    }

    @Test func legacyRoutineJSONDecodesAsUncategorized() throws {
        // A routine saved before categories existed has neither key.
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Old","routineDescription":"","source":"My Routines",
         "sourceURL":"","exercises":[],"accentColorName":"purple","systemImage":"dumbbell.fill"}
        """
        let decoded = try JSONDecoder().decode(SavedWorkoutRoutine.self, from: Data(legacy.utf8))
        #expect(decoded.category == nil)
        #expect(decoded.kind == nil)

        let grouped = RoutineFolders.folders(preloaded: [], user: [decoded])
        #expect(grouped.user.map(\.name) == [RoutineFolders.uncategorizedName])
    }

    @Test func userRoutineSavedAsCoreJoinsBuiltInFolder() {
        let grouped = RoutineFolders.folders(
            preloaded: PreloadedRoutines.all,
            user: [routine("Mine", category: " core ")]
        )
        let core = grouped.builtIn.first { $0.name == "Core" }
        #expect(core?.routines.count == 2)
        #expect(core?.routines.first?.source == "Athlean-X")
        #expect(grouped.user.isEmpty)
    }

    @Test func userFoldersSortAndUncategorizedComesLast() {
        let grouped = RoutineFolders.folders(
            preloaded: [],
            user: [
                routine("a"),
                routine("b", category: "zebra"),
                routine("c", category: "Apple"),
                routine("d", category: "APPLE")
            ]
        )
        #expect(grouped.user.map(\.name) == ["Apple", "zebra", "Uncategorized"])
        #expect(grouped.user.first?.routines.count == 2)
    }

    @Test func renameAndRemoveAffectOnlyThatFolder() {
        let routines = [
            routine("a", category: "Old"),
            routine("b", category: "old "),
            routine("c", category: "Other")
        ]
        let renamed = RoutineFolders.renaming(routines, from: "Old", to: "New")
        #expect(renamed.map(\.category) == ["New", "New", "Other"])

        let removed = RoutineFolders.removing(routines, category: "OLD")
        #expect(removed.map(\.name) == ["c"])
    }

    @Test func stretchKindIsRecordedAsFlexibilityRegardlessOfMoves() {
        let stretch = SavedWorkoutRoutine(
            name: "S", routineDescription: "", source: "You", sourceURL: "",
            exercises: [SavedRoutineExercise(name: "Cat-Cow", duration: 20, moveType: .move)],
            accentColorName: "teal", systemImage: "figure.flexibility", kind: .stretch
        )
        #expect(stretch.resolvedActivityType(intention: .hiit) == .flexibility)
    }
}

@MainActor
struct ActivityTypeTests {

    private func routine(
        kind: SavedRoutineKind?,
        moveType: SavedMoveType
    ) -> SavedWorkoutRoutine {
        SavedWorkoutRoutine(
            name: "R", routineDescription: "", source: "You", sourceURL: "",
            exercises: [
                SavedRoutineExercise(name: "A", duration: 30, moveType: moveType),
                SavedRoutineExercise(name: "B", duration: 30, moveType: moveType)
            ],
            accentColorName: "purple", systemImage: "star.fill", kind: kind
        )
    }

    @Test func intentionMapping() {
        #expect(WorkoutIntention.strengthPower.healthKitActivityType == .functionalStrengthTraining)
        #expect(WorkoutIntention.cardioEndurance.healthKitActivityType == .mixedCardio)
        #expect(WorkoutIntention.hiit.healthKitActivityType == .highIntensityIntervalTraining)
        #expect(WorkoutIntention.fatBurn.healthKitActivityType == .highIntensityIntervalTraining)
        #expect(WorkoutIntention.generalFitness.healthKitActivityType == .highIntensityIntervalTraining)
    }

    @Test func focusAreasDecideTheKind() {
        #expect(SavedRoutineKind.forFocusAreas(["Core"]) == .core)
        #expect(SavedRoutineKind.forFocusAreas(["Core", "Core: Strength"]) == .core)
        #expect(SavedRoutineKind.forFocusAreas(["Cardio"]) == .cardio)
        #expect(SavedRoutineKind.forFocusAreas(["Cool Down", "Warm-Up: Hips"]) == .stretch)
        // The Upper quick filter: not purely core/cardio, so the Intention decides.
        #expect(SavedRoutineKind.forFocusAreas(["Chest", "Shoulders", "Triceps"]) == .workout)
        #expect(SavedRoutineKind.forFocusAreas(["Core", "Cardio"]) == .workout)
        #expect(SavedRoutineKind.forFocusAreas([]) == .workout)
    }

    @Test func taggedKindOverridesIntention() {
        let core = routine(kind: .core, moveType: .move)
        #expect(core.resolvedActivityType(intention: .strengthPower) == .coreTraining)
        let cardio = routine(kind: .cardio, moveType: .move)
        #expect(cardio.resolvedActivityType(intention: .strengthPower) == .mixedCardio)
    }

    @Test func untaggedWorkoutFollowsIntention() {
        let general = routine(kind: .workout, moveType: .move)
        #expect(general.resolvedActivityType(intention: .strengthPower) == .functionalStrengthTraining)
        #expect(general.resolvedActivityType(intention: .cardioEndurance) == .mixedCardio)
        #expect(general.resolvedActivityType(intention: .generalFitness) == .highIntensityIntervalTraining)
    }

    @Test func flexibilityDetection() {
        // Mostly holds with no tag reads as stretching.
        #expect(routine(kind: nil, moveType: .hold).isFlexibilitySession)
        #expect(routine(kind: nil, moveType: .hold).resolvedActivityType(intention: .hiit) == .flexibility)
        // An explicit tag beats the ratio, in both directions.
        #expect(!routine(kind: .workout, moveType: .hold).isFlexibilitySession)
        #expect(routine(kind: .stretch, moveType: .move).isFlexibilitySession)
        #expect(!routine(kind: nil, moveType: .move).isFlexibilitySession)
    }

    @Test func preloadedRoutinesAreRecordedAsDescribed() {
        #expect(PreloadedRoutines.morningStretches.resolvedActivityType(intention: .hiit) == .flexibility)
        #expect(PreloadedRoutines.bedtimeStretches.resolvedActivityType(intention: .hiit) == .flexibility)
        #expect(PreloadedRoutines.absWorkout.resolvedActivityType(intention: .hiit) == .coreTraining)
        #expect(PreloadedRoutines.morningStretches.isFlexibilitySession)
        #expect(!PreloadedRoutines.absWorkout.isFlexibilitySession)
    }
}
