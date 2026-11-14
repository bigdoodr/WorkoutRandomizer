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

// MARK: - Plan + clock anchor

struct PlanClockTests {

    /// Three slots: 20 s work, 10 s rest, 20 s work.
    private func plan(id: String = "A", createdAt: TimeInterval = 1_000) -> WorkoutPlan {
        WorkoutPlan(id: id, createdAt: createdAt, slots: [
            PlanSlot(name: "Squats", isRest: false, duration: 20),
            PlanSlot(name: "Rest", isRest: true, duration: 10),
            PlanSlot(name: "Lunges", isRest: false, duration: 20),
        ])
    }

    @Test func freshSlotReadsItsFullDuration() {
        let p = plan()
        let a = PlanClock.startAnchor(planID: "A", now: 100, source: .phone)
        let pos = PlanClock.position(plan: p, anchor: a, at: 100)
        #expect(pos.slotIndex == 0)
        #expect(pos.remaining == 20)
        #expect(!pos.isFinished)
    }

    @Test func advancesThroughSlotsFromTheClockAlone() {
        let p = plan()
        let a = PlanClock.startAnchor(planID: "A", now: 100, source: .phone)
        // 25 s in: 5 s into the rest slot.
        let rest = PlanClock.position(plan: p, anchor: a, at: 125)
        #expect(rest.slotIndex == 1)
        #expect(rest.remaining == 5)
        // 31 s in: 1 s into the last slot.
        let last = PlanClock.position(plan: p, anchor: a, at: 131)
        #expect(last.slotIndex == 2)
        #expect(last.remaining == 19)
    }

    @Test func finishesAtTheEndOfThePlan() {
        let p = plan()
        let a = PlanClock.startAnchor(planID: "A", now: 100, source: .phone)
        let pos = PlanClock.position(plan: p, anchor: a, at: 150)
        #expect(pos.isFinished)
        #expect(pos.slotIndex == 3)
        #expect(PlanClock.position(plan: p, anchor: a, at: 9_999).isFinished)
    }

    @Test func pauseFreezesTimeAndResumeContinues() {
        let p = plan()
        let start = PlanClock.startAnchor(planID: "A", now: 100, source: .phone)
        let paused = PlanClock.paused(p, start, at: 112, by: .watch)
        #expect(!paused.isRunning)
        // However long it stays paused, the position doesn't move.
        let during = PlanClock.position(plan: p, anchor: paused, at: 500)
        #expect(during.slotIndex == 0)
        #expect(during.remaining == 8)
        // Resume at t=500: 8 s of slot 0 remain from there.
        let resumed = PlanClock.resumed(p, paused, at: 500, by: .watch)
        #expect(PlanClock.position(plan: p, anchor: resumed, at: 504).remaining == 4)
        #expect(PlanClock.position(plan: p, anchor: resumed, at: 509).slotIndex == 1)
    }

    @Test func skipJumpsToTheNextSlotAndKeepsRunState() {
        let p = plan()
        let start = PlanClock.startAnchor(planID: "A", now: 100, source: .phone)
        let skipped = PlanClock.skipped(p, start, at: 105, by: .watch)
        #expect(skipped.isRunning)
        let pos = PlanClock.position(plan: p, anchor: skipped, at: 105)
        #expect(pos.slotIndex == 1)
        #expect(pos.remaining == 10)
        // Skipping while paused stays paused.
        let paused = PlanClock.paused(p, start, at: 105, by: .phone)
        let skippedPaused = PlanClock.skipped(p, paused, at: 200, by: .phone)
        #expect(!skippedPaused.isRunning)
        #expect(PlanClock.position(plan: p, anchor: skippedPaused, at: 400).slotIndex == 1)
    }

    @Test func skippingTheLastSlotEndsThePlan() {
        let p = plan()
        let a = PlanClock.anchor(planID: "A", slotIndex: 2, secondsIntoSlot: 3, isRunning: true, now: 100, source: .phone)
        let skipped = PlanClock.skipped(p, a, at: 101, by: .watch)
        #expect(PlanClock.position(plan: p, anchor: skipped, at: 101).isFinished)
    }

    @Test func newerAnchorWinsRegardlessOfArrivalOrder() {
        let older = ClockAnchor(planID: "A", slotIndex: 0, secondsIntoSlot: 0, anchorDate: 100, isRunning: true, updatedAt: 100, source: .phone)
        let newer = ClockAnchor(planID: "A", slotIndex: 1, secondsIntoSlot: 0, anchorDate: 110, isRunning: false, updatedAt: 110, source: .watch)
        #expect(newer.supersedes(older))
        #expect(!older.supersedes(newer))
    }

    @Test func anExactTieGoesToThePhone() {
        let phone = ClockAnchor(planID: "A", slotIndex: 0, secondsIntoSlot: 0, anchorDate: 100, isRunning: true, updatedAt: 100, source: .phone)
        let watch = ClockAnchor(planID: "A", slotIndex: 1, secondsIntoSlot: 0, anchorDate: 100, isRunning: true, updatedAt: 100, source: .watch)
        #expect(phone.supersedes(watch))
        #expect(!watch.supersedes(phone))
    }

    @Test func anchorForAnotherPlanIsStale() {
        let current = ClockAnchor(planID: "A", slotIndex: 0, secondsIntoSlot: 0, anchorDate: 100, isRunning: true, updatedAt: 100, source: .phone)
        let otherPlan = ClockAnchor(planID: "B", slotIndex: 2, secondsIntoSlot: 0, anchorDate: 999, isRunning: true, updatedAt: 999, source: .phone)
        // Even though it's newer, it belongs to a different plan.
        #expect(!otherPlan.supersedes(current))
    }

    @Test func aPlanIsAdoptedOnlyIfNewOrNewer() {
        let current = plan(id: "A", createdAt: 1_000)
        #expect(PlanClock.shouldAdopt(plan(id: "B", createdAt: 2_000), over: current))
        #expect(!PlanClock.shouldAdopt(plan(id: "B", createdAt: 500), over: current))   // older plan arriving late
        #expect(!PlanClock.shouldAdopt(plan(id: "A", createdAt: 1_000), over: current)) // same plan again
        #expect(PlanClock.shouldAdopt(plan(id: "A"), over: nil))
    }

    @Test func positionSurvivesAnOutOfRangeAnchor() {
        let p = plan()
        let negative = ClockAnchor(planID: "A", slotIndex: -4, secondsIntoSlot: -3, anchorDate: 100, isRunning: true, updatedAt: 100, source: .phone)
        #expect(PlanClock.position(plan: p, anchor: negative, at: 100).slotIndex == 0)
        let beyond = ClockAnchor(planID: "A", slotIndex: 99, secondsIntoSlot: 0, anchorDate: 100, isRunning: true, updatedAt: 100, source: .phone)
        #expect(PlanClock.position(plan: p, anchor: beyond, at: 100).isFinished)
    }

    @Test func planSyncRoundTripsThroughJSON() throws {
        let sync = PlanSync(plan: plan(), anchor: PlanClock.startAnchor(planID: "A", now: 100, source: .phone))
        let decoded = try JSONDecoder().decode(PlanSync.self, from: JSONEncoder().encode(sync))
        #expect(decoded == sync)
    }
}

// MARK: - Zone resolution

@MainActor
struct ZoneResolverTests {

    @Test func theWatchsOwnZoneBeatsAnythingWorkedOutHere() {
        // 150 bpm against these boundaries would be Zone 4, but the Watch says Zone 2.
        let info = ZoneResolver.resolve(heartRate: 150, watchZoneIndex: 1, liveThresholds: [100, 120, 140, 160])
        #expect(info.index == 1)
        #expect(info.name == "Zone 2")
        #expect(info.burnType == "Fat Burn")
    }

    @Test func withoutAWatchZoneTheWatchsBoundariesClassifyTheHeartRate() {
        let boundaries: [Double] = [100, 120, 140, 160]
        #expect(ZoneResolver.resolve(heartRate: 90, watchZoneIndex: nil, liveThresholds: boundaries).index == 0)
        #expect(ZoneResolver.resolve(heartRate: 130, watchZoneIndex: nil, liveThresholds: boundaries).index == 2)
        #expect(ZoneResolver.resolve(heartRate: 150, watchZoneIndex: nil, liveThresholds: boundaries).index == 3)
        #expect(ZoneResolver.resolve(heartRate: 175, watchZoneIndex: nil, liveThresholds: boundaries).index == 4)
    }

    @Test func burnTypeFollowsTheZone() {
        #expect(ZoneResolver.info(forIndex: 0).burnType == "Active Recovery")
        #expect(ZoneResolver.info(forIndex: 1).burnType == "Fat Burn")
        #expect(ZoneResolver.info(forIndex: 2).burnType == "Mixed")
        #expect(ZoneResolver.info(forIndex: 3).burnType == "Carb Burn")
        #expect(ZoneResolver.info(forIndex: 4).burnType == "Peak Effort")
    }

    @Test func outOfRangeZoneIndexesAreClamped() {
        #expect(ZoneResolver.info(forIndex: -3).index == 0)
        #expect(ZoneResolver.info(forIndex: 9).index == 4)
    }
}

// MARK: - Plan display metadata (stretches)

struct PlanDisplayTests {

    @Test func slotsCountAsOwnItemsByDefault() {
        let plan = WorkoutPlan(id: "A", createdAt: 1, slots: [
            PlanSlot(name: "A", isRest: false, duration: 10),
            PlanSlot(name: "Rest", isRest: true, duration: 5),
            PlanSlot(name: "B", isRest: false, duration: 10),
        ])
        #expect(plan.progress(forSlot: 2) == (item: 3, total: 3))
        #expect(plan.nextName(afterSlot: 0) == "Rest")
        #expect(plan.nextName(afterSlot: 2) == nil)
    }

    @Test func groupedSlotsShareOneProgressItem() {
        // Two stretches; the first has two sides and a lead-in.
        let plan = WorkoutPlan(id: "S", createdAt: 1, slots: [
            PlanSlot(name: "Get Ready", isRest: true, duration: 5, groupIndex: 0, nextName: "Hamstring", hasNextName: true),
            PlanSlot(name: "Hamstring", isRest: false, duration: 20, sideLabel: "Left Side", groupIndex: 0, nextName: "Quad", hasNextName: true),
            PlanSlot(name: "Hamstring", isRest: false, duration: 20, sideLabel: "Right Side", groupIndex: 0, nextName: "Quad", hasNextName: true),
            PlanSlot(name: "Get Ready", isRest: true, duration: 5, groupIndex: 1, nextName: "Quad", hasNextName: true),
            PlanSlot(name: "Quad", isRest: false, duration: 20, groupIndex: 1, nextName: nil, hasNextName: true),
        ], groupCount: 2)
        // Both sides and the lead-in are "1 of 2"; the next stretch is "2 of 2".
        for slot in 0...2 { #expect(plan.progress(forSlot: slot) == (item: 1, total: 2)) }
        for slot in 3...4 { #expect(plan.progress(forSlot: slot) == (item: 2, total: 2)) }
        // A hold points at the next stretch, not at its own second side; the last has no next.
        #expect(plan.nextName(afterSlot: 1) == "Quad")
        #expect(plan.nextName(afterSlot: 3) == "Quad")
        #expect(plan.nextName(afterSlot: 4) == nil)
    }

    @Test func olderPlansWithoutTheNewFieldsStillDecode() throws {
        let json = #"{"id":"A","createdAt":1,"slots":[{"name":"X","isRest":false,"duration":9}]}"#
        let plan = try JSONDecoder().decode(WorkoutPlan.self, from: Data(json.utf8))
        #expect(plan.slots[0].groupIndex == nil)
        #expect(plan.groupCount == nil)
        #expect(plan.progress(forSlot: 0) == (item: 1, total: 1))
    }
}

// MARK: - Shared player clock

@MainActor
struct PlanPlayerClockTests {

    /// 10 s work, 5 s rest, 10 s work — driven with a fake clock and no timer.
    private func makeClock(start t0: TimeInterval = 1_000)
        -> (clock: PlanPlayerClock, log: ClockLog, time: TimeBox) {
        let time = TimeBox(t0)
        let log = ClockLog()
        let clock = PlanPlayerClock()
        clock.now = { time.value }
        clock.onElapsed = { slot, seconds in log.elapsed[slot, default: 0] += seconds }
        clock.onSlotChange = { from, to, reason in log.changes.append("\(from)->\(to):\(reason)") }
        clock.onFinish = { last, reason in log.finishes.append("\(last):\(reason)") }
        clock.onWarning = { log.warnings += 1 }
        clock.onPauseChange = { paused, byWatch in log.pauses.append("\(paused):\(byWatch)") }
        clock.link = PlanPlayerClock.Link(begin: { log.begun.append($0) }, send: { log.sent.append($0) })
        let plan = WorkoutPlan(id: "P", createdAt: t0, slots: [
            PlanSlot(name: "A", isRest: false, duration: 10),
            PlanSlot(name: "Rest", isRest: true, duration: 5),
            PlanSlot(name: "B", isRest: false, duration: 10),
        ])
        clock.start(plan: plan, usesTimer: false)
        return (clock, log, time)
    }

    @Test func startStampsTheAnchorAndTellsTheWatch() {
        let (clock, log, _) = makeClock()
        #expect(clock.isActive)
        #expect(clock.remaining == 10)
        #expect(log.begun.count == 1)
        #expect(log.begun[0].anchor.anchorDate == 1_000)
        #expect(log.begun[0].anchor.source == .phone)
    }

    @Test func ticksCountDownAndAdvanceFromTheClockAlone() {
        let (clock, log, _) = makeClock()
        clock.tick(at: 1_004)
        #expect(clock.remaining == 6)
        // A long stall: jump straight into the third slot.
        clock.tick(at: 1_017)
        #expect(clock.slotIndex == 2)
        #expect(clock.remaining == 8)
        #expect(log.changes == ["0->1:natural", "1->2:natural"])
        // Every second of the slots we passed through is accounted for exactly once.
        #expect(log.elapsed[0] == 10)
        #expect(log.elapsed[1] == 5)
        #expect(log.elapsed[2] == 2)
    }

    @Test func warnsAtThreeSeconds() {
        let (clock, log, _) = makeClock()
        clock.tick(at: 1_007)
        #expect(clock.remaining == 3)
        #expect(log.warnings == 1)
    }

    @Test func finishesOnceAtTheEnd() {
        let (clock, log, _) = makeClock()
        clock.tick(at: 1_030)
        #expect(!clock.isActive)
        #expect(log.finishes == ["2:natural"])
        // Further ticks do nothing.
        clock.tick(at: 1_040)
        #expect(log.finishes.count == 1)
    }

    @Test func pauseFreezesTheCountdownAndResumeContinues() {
        let (clock, log, time) = makeClock()
        time.value = 1_004
        #expect(clock.togglePause() == true)
        clock.tick(at: 1_500)                  // however long it stays paused...
        #expect(clock.remaining == 10)         // ...nothing has been counted down (tick is ignored)
        time.value = 1_500
        #expect(clock.togglePause() == false)
        clock.tick(at: 1_503)
        #expect(clock.remaining == 3)          // 6 s were left at the pause, 3 s later it's 3
        #expect(log.sent.count == 2)           // each re-anchor was sent
        #expect(log.sent[0].isRunning == false)
        #expect(log.sent[1].isRunning == true)
    }

    @Test func skipReAnchorsAndTellsTheWatch() {
        let (clock, log, time) = makeClock()
        time.value = 1_003
        clock.skip()
        #expect(clock.slotIndex == 1)
        #expect(clock.remaining == 5)
        #expect(log.changes == ["0->1:skipped"])
        #expect(log.sent.last?.slotIndex == 1)
        // The clock now runs from the new anchor, not the original start.
        clock.tick(at: 1_005)
        #expect(clock.remaining == 3)
    }

    @Test func skippingTheLastSlotFinishesWithoutSendingAnAnchor() {
        let (clock, log, time) = makeClock()
        time.value = 1_020
        clock.tick(at: 1_020)
        #expect(clock.slotIndex == 2)
        let sentBefore = log.sent.count
        clock.skip()
        #expect(log.finishes == ["2:skipped"])
        #expect(log.sent.count == sentBefore)
    }

    @Test func adoptingAWatchAnchorMovesThePlayerAndDoesNotEcho() {
        let (clock, log, time) = makeClock()
        time.value = 1_002
        let watchSkip = ClockAnchor(planID: "P", slotIndex: 1, secondsIntoSlot: 0, anchorDate: 1_002,
                                    isRunning: true, updatedAt: 1_002.5, source: .watch)
        clock.adopt(watchSkip)
        #expect(clock.slotIndex == 1)
        #expect(clock.remaining == 5)
        #expect(log.changes == ["0->1:watch"])
        #expect(log.sent.isEmpty)               // nothing sent back
        // A Watch pause is picked up too.
        let watchPause = ClockAnchor(planID: "P", slotIndex: 1, secondsIntoSlot: 2, anchorDate: 1_004,
                                     isRunning: false, updatedAt: 1_004, source: .watch)
        clock.adopt(watchPause)
        #expect(clock.isPaused)
        #expect(clock.remaining == 3)
        #expect(log.pauses == ["true:true"])
    }

    @Test func anAnchorForAnotherPlanIsIgnored() {
        let (clock, log, _) = makeClock()
        let stale = ClockAnchor(planID: "OLD", slotIndex: 2, secondsIntoSlot: 0, anchorDate: 1_001,
                                isRunning: true, updatedAt: 1_001, source: .watch)
        clock.adopt(stale)
        #expect(clock.slotIndex == 0)
        #expect(log.changes.isEmpty)
    }

    @Test func aWatchSkipPastTheEndFinishesThePlayer() {
        let (clock, log, _) = makeClock()
        let end = ClockAnchor(planID: "P", slotIndex: 3, secondsIntoSlot: 0, anchorDate: 1_001,
                              isRunning: true, updatedAt: 1_001, source: .watch)
        clock.adopt(end)
        #expect(log.finishes == ["2:watch"])
        #expect(log.changes == ["0->1:watch", "1->2:watch"])
    }
}

@MainActor
private final class ClockLog {
    var elapsed: [Int: Int] = [:]
    var changes: [String] = []
    var finishes: [String] = []
    var warnings = 0
    var pauses: [String] = []
    var begun: [PlanSync] = []
    var sent: [ClockAnchor] = []
}

@MainActor
private final class TimeBox {
    var value: TimeInterval
    init(_ value: TimeInterval) { self.value = value }
}

// MARK: - Stretch plan

struct StretchPlanTests {

    private let items = [
        StretchPlanItem(name: "Hamstring", singleSided: true),
        StretchPlanItem(name: "Cat-Cow", singleSided: false),
        StretchPlanItem(name: "Quad", singleSided: true),
    ]

    @Test func bothSidesAndGetReadySlotsAreLaidOutInOrder() {
        let (plan, roles) = StretchPlanBuilder.build(items: items, holdDuration: 20, bothSides: true,
                                                     transitionDuration: 5, leadIn: false, activityTypeRaw: nil)
        #expect(plan.slots.map(\.name) == ["Hamstring", "Hamstring", "Get Ready", "Cat-Cow", "Get Ready", "Quad", "Quad"])
        #expect(plan.slots.map(\.sideLabel) == ["Left Side", "Right Side", nil, nil, nil, "Left Side", "Right Side"])
        #expect(plan.slots.map(\.duration) == [20, 20, 5, 20, 5, 20, 20])
        #expect(plan.slots.map(\.isRest) == [false, false, true, false, true, false, false])
        #expect(roles.map(\.isTransition) == [false, false, true, false, true, false, false])
        #expect(roles.map(\.stretchIndex) == [0, 0, 1, 1, 2, 2, 2])
        #expect(roles.map(\.side) == [0, 1, 0, 0, 0, 0, 1])
        #expect(plan.groupCount == 3)
    }

    @Test func oneSideOnlyWhenBothSidesIsOff() {
        let (plan, _) = StretchPlanBuilder.build(items: items, holdDuration: 30, bothSides: false,
                                                 transitionDuration: 5, leadIn: false, activityTypeRaw: nil)
        #expect(plan.slots.map(\.name) == ["Hamstring", "Get Ready", "Cat-Cow", "Get Ready", "Quad"])
        #expect(plan.slots.allSatisfy { $0.sideLabel == nil })
    }

    @Test func aLeadInAddsAGetReadyBeforeTheFirstStretch() {
        let (plan, roles) = StretchPlanBuilder.build(items: items, holdDuration: 20, bothSides: true,
                                                     transitionDuration: 5, leadIn: true, activityTypeRaw: nil)
        #expect(plan.slots.first?.name == "Get Ready")
        #expect(plan.slots.first?.nextName == "Hamstring")
        #expect(roles.first == StretchSlotRole(stretchIndex: 0, side: 0, isTransition: true))
        #expect(plan.slots.count == 8)
    }

    @Test func progressAndNextMatchWhatTheWatchUsedToShow() {
        let (plan, _) = StretchPlanBuilder.build(items: items, holdDuration: 20, bothSides: true,
                                                 transitionDuration: 5, leadIn: false, activityTypeRaw: nil)
        // Both sides of the first stretch are "1 of 3"; the Get Ready before the second is "2 of 3".
        #expect(plan.progress(forSlot: 0) == (item: 1, total: 3))
        #expect(plan.progress(forSlot: 1) == (item: 1, total: 3))
        #expect(plan.progress(forSlot: 2) == (item: 2, total: 3))
        // A hold's "Next" is the next stretch; a Get Ready's is the stretch it leads into; the last has none.
        #expect(plan.nextName(afterSlot: 0) == "Cat-Cow")
        #expect(plan.nextName(afterSlot: 2) == "Cat-Cow")
        #expect(plan.nextName(afterSlot: 6) == nil)
    }

    @Test func totalLengthMatchesTheOldEstimate() {
        let (plan, _) = StretchPlanBuilder.build(items: items, holdDuration: 20, bothSides: true,
                                                 transitionDuration: 5, leadIn: false, activityTypeRaw: nil)
        // Holds: 2 + 1 + 2 sides at 20 s, plus two 5 s Get Readys = 110 s.
        #expect(plan.totalSeconds == 110)
    }
}
