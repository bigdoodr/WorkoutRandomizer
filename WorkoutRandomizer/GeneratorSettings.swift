//  GeneratorSettings.swift
//  Bodyweight WorkoutRandomizer
//
//  Every timing choice for a generated workout — timer style, durations, rest, warm-up/cool-down,
//  and the Repeating Blocks and Pyramid options — in one shared object. The Timer tab edits it and
//  the Generate tab reads it, so the two can't drift apart and neither needs to own the other's state.
//
//  Moved out of WorkoutGeneratorView, where it was ~30 separate @State vars. The helpers below are
//  the same arithmetic that lived beside them there.

import SwiftUI
import Observation

/// Where a generated workout's exercises come from.
enum GenerationSource: String, CaseIterable, Identifiable {
    /// Drawn at random from the selected focus areas, difficulties and equipment.
    case random = "Random"
    /// The exercises queued in Build Your Own.
    case myList = "My List"
    var id: String { rawValue }
}

/// How My List feeds the generator.
enum ListMode: String, CaseIterable, Identifiable {
    /// Every listed exercise once, in order (or shuffled).
    case performAll = "Perform all"
    /// The list is a pool: the generator fills the chosen length by drawing from it.
    case drawFrom = "Draw from"
    var id: String { rawValue }
}

@MainActor
@Observable
final class GeneratorSettings {
    static let shared = GeneratorSettings()

    // MARK: Source

    var source: GenerationSource = .random
    var listMode: ListMode = .performAll
    /// Perform all only: shuffle the order of the list instead of running it as written.
    var shuffleListOrder = false

    /// Pyramid sizes its exercise count from Total Duration, so it can't "perform all" of an
    /// arbitrary list — with Pyramid the list is always used as a pool.
    var performAllAvailable: Bool { timerStyle != .pyramid }

    /// True when generation should run the list exactly as written.
    var usesPerformAll: Bool {
        source == .myList && listMode == .performAll && performAllAvailable
    }

    // MARK: Durations

    var totalDuration = 10
    var exerciseDuration = 20
    /// The manually-chosen rest, used only when the link to exercise duration is off.
    var restDuration = 10
    var restEvery = 1
    var shuffleExerciseTime = false
    var timerStyle: TimerStyle = .standard

    // MARK: Repeating Blocks

    var blocksCount = 3
    var exercisesPerBlock = 3
    var blockDurations = [30, 25, 45]
    var blocksTotalSets = 2
    var shuffleBlockSets = false
    /// Linked (default): the rest between full cycles is the same derived value as the rest
    /// after any other exercise. Manual: a longer, hand-picked rest before the whole block of
    /// exercises repeats.
    var blocksCycleRestLinked = true
    var blocksCycleRestDuration = 60

    // MARK: Pyramid

    /// Off (default): an exercise keeps the same duration on both sides of the climb. On: each
    /// rung gets its own independent pick, so that pairing isn't guaranteed.
    var shufflePyramidOrder = false

    // MARK: Persisted across launches (same keys the views' @AppStorage used)

    /// When on, rest is derived from exercise duration instead of set by hand.
    var restLinkedToWork: Bool {
        didSet { UserDefaults.standard.set(restLinkedToWork, forKey: "restLinkedToWork") }
    }
    var addWarmUp: Bool {
        didSet { UserDefaults.standard.set(addWarmUp, forKey: "addWarmUp") }
    }
    var addCoolDown: Bool {
        didSet { UserDefaults.standard.set(addCoolDown, forKey: "addCoolDown") }
    }

    private init() {
        let defaults = UserDefaults.standard
        restLinkedToWork = defaults.object(forKey: "restLinkedToWork") as? Bool ?? true
        addWarmUp = defaults.bool(forKey: "addWarmUp")
        addCoolDown = defaults.bool(forKey: "addCoolDown")
    }

    // MARK: Constants

    /// Shuffle Exercise Time draws from the same presets as the Exercise Duration chips.
    static let shuffleExerciseDurationOptions = [20, 30, 45, 60]
    /// Each warm-up move runs this long; cool-down holds run longer to be worth doing.
    static let warmUpSecondsPerMove = 30
    static let coolDownSecondsPerHold = 30
    static let coolDownHoldCount = 2

    // MARK: Derived

    /// The rest that Standard routines actually use: derived from exercise duration while the
    /// link is on, the hand-picked value otherwise. Everything downstream — the timing resolver,
    /// the player, the routine-length estimate — must read this, never `restDuration`.
    var effectiveRestDuration: Int {
        restLinkedToWork ? WorkoutTiming.restSeconds(forWork: exerciseDuration) : restDuration
    }

    /// Work + derived rest for one pass through every block.
    var blocksSuperSetSeconds: Int {
        blockDurations.reduce(0) { total, work in
            total + exercisesPerBlock * (work + WorkoutTiming.restSeconds(forWork: work))
        }
    }

    /// The routine has no trailing rest after its final exercise, so the honest total is one
    /// rest shorter than the raw cycle arithmetic suggests.
    private var blocksTrailingRestSeconds: Int {
        guard let lastWork = blockDurations.last else { return 0 }
        return WorkoutTiming.restSeconds(forWork: lastWork)
    }

    /// The rest Blocks actually uses between full cycles: derived from the last block's work
    /// while linked, the hand-picked value otherwise. Everything downstream — the timing
    /// resolver and the length estimate — must read this, never `blocksCycleRestDuration`.
    var effectiveBlocksCycleRest: Int {
        blocksCycleRestLinked ? blocksTrailingRestSeconds : blocksCycleRestDuration
    }

    func blocksTotalSeconds(forSets sets: Int) -> Int {
        guard sets > 0 else { return 0 }
        let workPerCycle = blockDurations.reduce(0) { $0 + exercisesPerBlock * $1 }
        let intraRestPerCycle = blocksSuperSetSeconds - workPerCycle - blocksTrailingRestSeconds
        let cycleGaps = max(0, sets - 1) * effectiveBlocksCycleRest
        return max(0, sets * (workPerCycle + intraRestPerCycle) + cycleGaps)
    }

    var blocksAvailableTotalSets: [Int] {
        guard blocksSuperSetSeconds > 0 else { return [1] }
        var options: [Int] = []
        var n = 1
        while blocksTotalSeconds(forSets: n) <= 90 * 60 { options.append(n); n += 1 }
        return options.isEmpty ? [1] : options
    }

    var blocksTotalSeconds: Int { blocksTotalSeconds(forSets: blocksTotalSets) }

    func clampBlocksTotalSets() {
        let options = blocksAvailableTotalSets
        if !options.contains(blocksTotalSets) { blocksTotalSets = options.first ?? 1 }
    }

    /// The pyramid sized for the currently-selected total duration.
    var pyramidPlan: WorkoutTiming.PyramidPlan {
        WorkoutTiming.pyramidPlan(forTotalMinutes: totalDuration)
    }

    /// Human-readable size of the warm-up that would be added at the current total duration.
    var warmUpSummary: String {
        let targetSeconds = max(Self.warmUpSecondsPerMove, totalDuration * 60 / 10)
        let moves = min(8, max(1, targetSeconds / Self.warmUpSecondsPerMove))
        return "\(moves) × \(Self.warmUpSecondsPerMove)s"
    }

    var coolDownSummary: String {
        "\(Self.coolDownHoldCount) × \(Self.coolDownSecondsPerHold)s"
    }

    /// Exactly `slots` exercise slots taken from the units in order, cycling through the list if
    /// it runs out. A Left/Right pair is never split: a pair that won't fit the last slot is
    /// skipped in favour of a later single. (Repeating Blocks needs a set of exactly this size.)
    static func fitUnits(_ units: [[Exercise]], toSlots slots: Int) -> [Exercise] {
        guard !units.isEmpty, slots > 0 else { return [] }
        var result: [Exercise] = []
        var index = 0
        var skippedInARow = 0
        while result.count < slots {
            let unit = units[index % units.count]
            index += 1
            if result.count + unit.count <= slots {
                result += unit
                skippedInARow = 0
            } else {
                skippedInARow += 1
                if skippedInARow >= units.count { break }   // only pairs left, and none fit
            }
        }
        return result
    }

    func formatBlockTime(_ seconds: Int) -> String {
        let m = seconds / 60; let s = seconds % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }

    /// The one place timing rules live. `overrides` are the Custom Timers edits made to the
    /// currently generated routine — they belong to that routine's slots, not to these settings.
    func timing(overrides: [Int: Int]) -> WorkoutTiming {
        WorkoutTiming(
            style: timerStyle,
            exerciseDuration: exerciseDuration,
            restDuration: effectiveRestDuration,
            blocksConfig: timerStyle == .blocks
                ? RepeatingBlocksConfig(
                    exercisesPerBlock: exercisesPerBlock,
                    blockDurations: blockDurations,
                    cycleRestSeconds: blocksTotalSets > 1 ? effectiveBlocksCycleRest : nil
                  )
                : nil,
            overrides: overrides,
            pyramidLadder: pyramidPlan.ladder
        )
    }
}
