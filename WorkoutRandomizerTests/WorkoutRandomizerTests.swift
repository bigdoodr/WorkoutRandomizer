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
struct RoutineImportTests {

    private func sampleRoutine() -> SavedWorkoutRoutine {
        SavedWorkoutRoutine(
            name: "Push Day",
            routineDescription: "Chest and shoulders",
            source: "You",
            sourceURL: "",
            exercises: [
                SavedRoutineExercise(name: "Push-Up", duration: 40, restDuration: 15, moveType: .move),
                SavedRoutineExercise(name: "Hip Flexor Stretch", duration: 30, restDuration: 5,
                                     singleSided: true, restAfterEachSide: true, moveType: .hold)
            ],
            accentColorName: "teal",
            systemImage: "bolt.fill",
            category: "Man of Steel",
            kind: .workout
        )
    }

    private func encoded(_ routine: SavedWorkoutRoutine) throws -> Data {
        try JSONEncoder().encode(RoutineExportFile(routine: routine))
    }

    @Test func roundTripKeepsEverythingButTheIDs() throws {
        let original = sampleRoutine()
        let imported = try #require(RoutineImport.parse(try encoded(original), fallbackName: "ignored"))

        #expect(imported.name == "Push Day")
        #expect(imported.category == "Man of Steel")
        #expect(imported.kind == .workout)
        #expect(imported.accentColorName == "teal")
        #expect(imported.systemImage == "bolt.fill")
        #expect(imported.exercises.map(\.name) == ["Push-Up", "Hip Flexor Stretch"])
        #expect(imported.exercises.map(\.duration) == [40, 30])
        #expect(imported.exercises.map(\.restDuration) == [15, 5])
        #expect(imported.exercises[1].singleSided)
        #expect(imported.exercises[1].restAfterEachSide)
        #expect(imported.exercises[1].moveType == .hold)

        // A re-imported file must never collide with the routine it came from.
        #expect(imported.id != original.id)
        #expect(Set(imported.exercises.map(\.id)).isDisjoint(with: original.exercises.map(\.id)))
    }

    @Test func oldExportedWorkoutsStillImport() throws {
        let legacy = [
            ExportableExercise(name: "Squat", isTimeBased: true, exerciseDuration: 45, restDuration: 20, sets: 1),
            ExportableExercise(name: "Rest", isTimeBased: true, exerciseDuration: 20, restDuration: 0, sets: 1),
            ExportableExercise(name: "Lunge (Left)", isTimeBased: true, exerciseDuration: 30, restDuration: 15, sets: 1),
            ExportableExercise(name: "Rest", isTimeBased: true, exerciseDuration: 15, restDuration: 0, sets: 1),
            ExportableExercise(name: "Lunge (Right)", isTimeBased: true, exerciseDuration: 30, restDuration: 10, sets: 1)
        ]
        let data = try JSONEncoder().encode(legacy)
        let imported = try #require(RoutineImport.parse(data, fallbackName: "Old Workout"))

        #expect(imported.name == "Old Workout")
        #expect(imported.category == nil)
        // The standalone Rest entries fold into the exercise before them.
        #expect(imported.exercises.map(\.name) == ["Squat", "Lunge (Left)", "Lunge (Right)"])
        #expect(imported.exercises.map(\.duration) == [45, 30, 30])
        #expect(imported.exercises.map(\.restDuration) == [20, 15, 0])
    }

    @Test func unreadableOrEmptyFilesAreRejected() throws {
        #expect(RoutineImport.parse(Data("not json".utf8), fallbackName: "x") == nil)
        #expect(RoutineImport.parse(Data("{\"hello\": 1}".utf8), fallbackName: "x") == nil)
        #expect(RoutineImport.parse(Data("[]".utf8), fallbackName: "x") == nil)

        var empty = sampleRoutine()
        empty.exercises = []
        #expect(RoutineImport.parse(try encoded(empty), fallbackName: "x") == nil)

        // Valid JSON of the right shape but from some other app's format.
        let wrongFormat = """
        {"format":"SomethingElse","version":1,"routine":{}}
        """
        #expect(RoutineImport.parse(Data(wrongFormat.utf8), fallbackName: "x") == nil)
    }

    @Test func outOfRangeTimingsAreClamped() throws {
        var wild = sampleRoutine()
        wild.exercises = [
            SavedRoutineExercise(name: "A", duration: 0, restDuration: -5),
            SavedRoutineExercise(name: "B", duration: 999_999, restDuration: 999_999)
        ]
        let imported = try #require(RoutineImport.parse(try encoded(wild), fallbackName: "x"))
        #expect(imported.exercises.map(\.duration) == [1, 3600])
        #expect(imported.exercises.map(\.restDuration) == [0, 3600])
    }

    @Test func exportedDocumentDecodesBackToTheSameRoutine() throws {
        let data = try RoutineDocument(routine: sampleRoutine()).encodedData()
        let imported = try #require(RoutineImport.parse(data, fallbackName: "x"))
        #expect(imported.name == "Push Day")
        #expect(imported.exercises.count == 2)
    }
}

@MainActor
struct MyListGenerationTests {

    private func ex(_ name: String) -> Exercise {
        Exercise(name: name, videoPath: nil, equipment: ["None"])
    }

    private func names(_ list: [Exercise]) -> [String] { list.map(\.name) }

    @Test func fitsExactlyTheRequestedSlotsInOrder() {
        let units = [[ex("A")], [ex("B")], [ex("C")]]
        #expect(names(GeneratorSettings.fitUnits(units, toSlots: 2)) == ["A", "B"])
        #expect(names(GeneratorSettings.fitUnits(units, toSlots: 3)) == ["A", "B", "C"])
    }

    @Test func cyclesBackToTheStartWhenTheListIsShorter() {
        let units = [[ex("A")], [ex("B")]]
        #expect(names(GeneratorSettings.fitUnits(units, toSlots: 5)) == ["A", "B", "A", "B", "A"])
    }

    @Test func neverSplitsALeftRightPair() {
        let pair = [ex("Lunge (Left)"), ex("Lunge (Right)")]
        let units = [[ex("A")], pair, [ex("B")]]
        // 2 slots: A, then the pair can't fit the last slot, so B takes it.
        #expect(names(GeneratorSettings.fitUnits(units, toSlots: 2)) == ["A", "B"])
        // 3 slots: A + the whole pair.
        #expect(names(GeneratorSettings.fitUnits(units, toSlots: 3)) == ["A", "Lunge (Left)", "Lunge (Right)"])
    }

    @Test func emptyListOrZeroSlotsYieldNothing() {
        #expect(GeneratorSettings.fitUnits([], toSlots: 4).isEmpty)
        #expect(GeneratorSettings.fitUnits([[ex("A")]], toSlots: 0).isEmpty)
    }

    @Test func aListOfOnlyPairsStopsShortRatherThanSplittingOne() {
        let units = [[ex("X (Left)"), ex("X (Right)")]]
        let result = GeneratorSettings.fitUnits(units, toSlots: 3)
        #expect(names(result) == ["X (Left)", "X (Right)"])
    }

    @Test func performAllNeedsAStyleWhoseCountFollowsTheList() {
        let settings = GeneratorSettings.shared
        let saved = (settings.source, settings.listMode, settings.timerStyle)
        defer { (settings.source, settings.listMode, settings.timerStyle) = saved }

        settings.source = .myList
        settings.listMode = .performAll
        for style in [TimerStyle.standard, .blocks, .addOn, .addOnTakeAway] {
            settings.timerStyle = style
            #expect(settings.usesPerformAll)
        }
        settings.timerStyle = .pyramid
        #expect(!settings.usesPerformAll)

        settings.timerStyle = .standard
        settings.listMode = .drawFrom
        #expect(!settings.usesPerformAll)
        settings.listMode = .performAll
        settings.source = .random
        #expect(!settings.usesPerformAll)
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

    @Test func sideStepsShareTheBaseExercisesVideo() throws {
        let entry = try #require(ExerciseCatalog.shared.videoPaths.first)
        let videos = VideoManager.shared
        #expect(videos.path(for: "\(entry.key) (Left)") == entry.value)
        #expect(videos.path(for: "\(entry.key) (Right)") == entry.value)
        #expect(videos.path(for: "Definitely Not An Exercise (Left)") == nil)
    }

    @Test func preloadedRoutinesAreRecordedAsDescribed() {
        #expect(PreloadedRoutines.morningStretches.resolvedActivityType(intention: .hiit) == .flexibility)
        #expect(PreloadedRoutines.bedtimeStretches.resolvedActivityType(intention: .hiit) == .flexibility)
        #expect(PreloadedRoutines.absWorkout.resolvedActivityType(intention: .hiit) == .coreTraining)
        #expect(PreloadedRoutines.morningStretches.isFlexibilitySession)
        #expect(!PreloadedRoutines.absWorkout.isFlexibilitySession)
    }
}

// MARK: - Guide release tracking

struct AppReleaseTests {
    @Test func versionOrdersBeforeBuild() {
        // Builds restart per version, so a higher build on an older version must not win.
        #expect(AppRelease("2.2", build: 9) < AppRelease("2.3", build: 1))
        #expect(AppRelease("2.3", build: 1) < AppRelease("2.3", build: 2))
    }

    @Test func equivalentVersionsAreEqual() {
        #expect(AppRelease("2") == AppRelease("2.0"))
        #expect(AppRelease("2.10") > AppRelease("2.9"))
    }

    @Test func nothingNewerThanCurrentMeansNoWhatsNew() {
        #expect(!TutorialView.hasPages(newerThan: AppRelease("99.0")))
        #expect(!TutorialView.hasPages(newerThan: AppRelease.current))
    }

    @Test func existingUsersSeeUpdatesSinceTwoPointZero() {
        #expect(TutorialView.hasPages(newerThan: AppRelease("2.0")))
        #expect(TutorialView.lastSeenRelease(version: "", build: 0) == nil)
    }
}
