//  WorkoutTiming.swift
//  Bodyweight WorkoutRandomizer
//
//  Single source of truth for "how long does the slot at index N run?".
//
//  Before this type existed the same rules were implemented three times: once in
//  WorkoutGeneratorView.defaultDuration(forIndex:exercise:) so the Custom Timers editor could
//  show the real default, once in WorkoutPlayerView.durationForCurrentPosition to actually run
//  the clock, and a third partial copy inline in the Blocks progress label. Any change to the
//  timing rules had to be made in all three, in lockstep, or they would silently disagree.
//
//  Behaviour here is deliberately identical to what those three copies did.

import SwiftUI

struct WorkoutTiming {
    let style: TimerStyle
    let exerciseDuration: Int
    let restDuration: Int
    let blocksConfig: RepeatingBlocksConfig?
    /// Per-slot user overrides from the Custom Timers editor, keyed by routine index.
    var overrides: [Int: Int] = [:]

    /// The Pyramid ladder: one work/rest pair per phase, repeating to fill the routine.
    /// NOTE: rest currently equals work here, and the ladder is a fixed 480s (8 minute) cycle —
    /// both are slated to change (duration-derived ladder, rest = work / 2).
    static let pyramidIntervals: [(work: Int, rest: Int)] = [
        (30, 30), (40, 40), (50, 50), (50, 50), (40, 40), (30, 30)
    ]

    // MARK: - Position

    /// How many work slots precede `index`. This is the positional basis for both the Pyramid
    /// phase and the Blocks index: a rest slot inherits the position of the exercise it follows,
    /// so work and its trailing rest resolve to the same phase/block.
    ///
    /// Anything inserted ahead of the work itself (a warm-up, say) shifts every phase and block
    /// downstream — that is why prepended items will need to be excluded from this count.
    func exercisePosition(at index: Int, in routine: [Exercise]) -> Int {
        let upper = min(max(index, 0), routine.count)
        let workBefore = routine[0..<upper].filter { $0.name != "Rest" }.count
        let isRest = routine.indices.contains(index) && routine[index].name == "Rest"
        return isRest ? max(0, workBefore - 1) : workBefore
    }

    /// Zero-based Pyramid phase for the slot at `index`; always 0 for other timer styles.
    func pyramidPhase(at index: Int, in routine: [Exercise]) -> Int {
        guard style == .pyramid else { return 0 }
        return exercisePosition(at: index, in: routine) % Self.pyramidIntervals.count
    }

    struct BlockPosition {
        let blockIndex: Int   // zero-based
        let setNumber: Int    // one-based cycle through all blocks
        let blockCount: Int
    }

    /// Which block (and which cycle through the blocks) the slot at `index` belongs to.
    /// Returns nil unless the Repeating Blocks style is active and configured.
    func blockPosition(at index: Int, in routine: [Exercise]) -> BlockPosition? {
        guard style == .blocks, let config = blocksConfig else { return nil }
        let position = exercisePosition(at: index, in: routine)
        let superSetSize = config.blockDurations.count * config.exercisesPerBlock
        let positionInSuperSet = position % max(1, superSetSize)
        let blockIndex = min(
            positionInSuperSet / max(1, config.exercisesPerBlock),
            config.blockDurations.count - 1
        )
        return BlockPosition(
            blockIndex: blockIndex,
            setNumber: position / max(1, superSetSize) + 1,
            blockCount: config.blockDurations.count
        )
    }

    // MARK: - Duration

    /// The duration the timer style dictates for this slot, ignoring any user override.
    /// Use this when showing what a slot *would* run, before per-slot customisation.
    func baseDuration(at index: Int, in routine: [Exercise]) -> Int {
        guard routine.indices.contains(index) else { return 0 }
        let isRest = routine[index].name == "Rest"

        switch style {
        case .pyramid:
            let interval = Self.pyramidIntervals[pyramidPhase(at: index, in: routine)]
            return isRest ? interval.rest : interval.work

        case .blocks:
            // Blocks has no separate rest value — work and rest share the block's duration.
            guard let config = blocksConfig,
                  let position = blockPosition(at: index, in: routine) else {
                return isRest ? restDuration : exerciseDuration
            }
            return config.blockDurations[position.blockIndex]

        case .standard:
            return isRest ? restDuration : exerciseDuration
        }
    }

    /// The duration that will actually run: a Custom Timers override always wins over the
    /// style default. This is the value the clock counts down and the one that should be
    /// recorded when a routine is saved or exported.
    func duration(at index: Int, in routine: [Exercise]) -> Int {
        guard routine.indices.contains(index) else { return 0 }
        return overrides[index] ?? baseDuration(at: index, in: routine)
    }
}
