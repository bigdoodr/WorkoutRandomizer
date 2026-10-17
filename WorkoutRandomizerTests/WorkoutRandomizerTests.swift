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
