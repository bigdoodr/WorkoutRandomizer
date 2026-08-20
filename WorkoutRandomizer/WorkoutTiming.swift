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

    // MARK: - Rest ratio

    /// The one rule that turns a work duration into its rest: half the work, rounded down to a
    /// 5-second boundary, never below 5s. Integer division does the rounding for free —
    /// 45s → 20s, 30s → 15s, 20s → 10s, 60s → 30s.
    ///
    /// Standard lets you opt out of this via the Rest Duration chips. Pyramid and Blocks have no
    /// manual rest input of their own, so they always derive rest from their work values.
    static func restSeconds(forWork work: Int) -> Int {
        max(5, (work / 2 / 5) * 5)
    }

    // MARK: - Pyramid ladder

    static let pyramidFloor = 20
    static let pyramidCeiling = 60
    /// Fits whose running time is within this of the best are treated as equally accurate, so
    /// shape can win the tie-break.
    static let pyramidTieToleranceSeconds = 30

    /// One symmetric pass: ramps floor → ceiling across the first half, then mirrors it.
    /// Values snap to 5s, so longer passes naturally develop plateaus rather than 1s increments.
    static func pyramidPass(steps: Int) -> [Int] {
        let half = max(1, steps / 2)
        var ascending: [Int] = []
        for i in 0..<half {
            let t = half == 1 ? 0.0 : Double(i) / Double(half - 1)
            let raw = Double(pyramidFloor) + t * Double(pyramidCeiling - pyramidFloor)
            ascending.append(Int((raw / 5.0).rounded()) * 5)
        }
        return ascending + ascending.reversed()
    }

    struct PyramidPlan {
        let pass: [Int]
        let repeats: Int
        var ladder: [Int] { Array(repeating: pass, count: repeats).flatMap { $0 } }
        var totalSeconds: Int { ladder.reduce(0) { $0 + $1 + WorkoutTiming.restSeconds(forWork: $1) } }
    }

    /// Choose a pyramid that fills the requested duration. Rather than repeating one fixed
    /// 8-minute cycle regardless of what was asked for, this searches pass lengths and repeat
    /// counts, then — among fits of comparable accuracy — prefers the longest single pass and
    /// the fewest repeats, because one 20-step climb reads better than two 10-step climbs.
    static func pyramidPlan(forTotalMinutes minutes: Int) -> PyramidPlan {
        let target = max(60, minutes * 60)
        var best: (error: Int, steps: Int, repeats: Int)?
        var candidates: [(error: Int, steps: Int, repeats: Int)] = []

        for steps in stride(from: 6, through: 24, by: 2) {
            let passSeconds = pyramidPass(steps: steps).reduce(0) { $0 + $1 + restSeconds(forWork: $1) }
            guard passSeconds > 0 else { continue }
            for repeats in 1...12 {
                let candidate = (error: abs(passSeconds * repeats - target), steps: steps, repeats: repeats)
                candidates.append(candidate)
                if best == nil || candidate.error < best!.error { best = candidate }
            }
        }

        guard let bestError = best?.error else {
            return PyramidPlan(pass: pyramidPass(steps: 10), repeats: 1)
        }
        let acceptable = candidates.filter { $0.error <= bestError + pyramidTieToleranceSeconds }
        let choice = acceptable.max { a, b in (a.steps, -a.repeats) < (b.steps, -b.repeats) }
            ?? (error: bestError, steps: 10, repeats: 1)
        return PyramidPlan(pass: pyramidPass(steps: choice.steps), repeats: choice.repeats)
    }

    /// The work sequence this session will actually run, one entry per exercise slot.
    var pyramidLadder: [Int] = WorkoutTiming.pyramidPass(steps: 10)

    /// One work/rest pair per Pyramid phase.
    var pyramidIntervals: [(work: Int, rest: Int)] {
        pyramidLadder.map { (work: $0, rest: Self.restSeconds(forWork: $0)) }
    }

    // MARK: - Position

    /// How many work slots precede `index`. This is the positional basis for both the Pyramid
    /// phase and the Blocks index: a rest slot inherits the position of the exercise it follows,
    /// so work and its trailing rest resolve to the same phase/block.
    ///
    /// Anything inserted ahead of the work itself (a warm-up, say) shifts every phase and block
    /// downstream — that is why prepended items will need to be excluded from this count.
    func exercisePosition(at index: Int, in routine: [Exercise]) -> Int {
        let upper = min(max(index, 0), routine.count)
        // Warm-up and cool-down slots are skipped entirely. Counting them would shift every
        // Pyramid phase and Blocks index downstream — a 3-exercise warm-up with 3 exercises
        // per block would silently start the routine on Block 2.
        let workBefore = routine[0..<upper].filter { $0.name != "Rest" && !$0.isPreparation }.count
        let isRest = routine.indices.contains(index) && routine[index].name == "Rest"
        return isRest ? max(0, workBefore - 1) : workBefore
    }

    /// Zero-based Pyramid phase for the slot at `index`; always 0 for other timer styles.
    func pyramidPhase(at index: Int, in routine: [Exercise]) -> Int {
        guard style == .pyramid, !pyramidIntervals.isEmpty else { return 0 }
        return exercisePosition(at: index, in: routine) % pyramidIntervals.count
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
        // Warm-up and cool-down carry their own duration and ignore the timer style.
        if let preparation = routine[index].preparationDuration { return preparation }
        let isRest = routine[index].name == "Rest"

        switch style {
        case .pyramid:
            guard !pyramidIntervals.isEmpty else { return isRest ? restDuration : exerciseDuration }
            let interval = pyramidIntervals[pyramidPhase(at: index, in: routine)]
            return isRest ? interval.rest : interval.work

        case .blocks:
            guard let config = blocksConfig,
                  let position = blockPosition(at: index, in: routine) else {
                return isRest ? restDuration : exerciseDuration
            }
            // Blocks configures work only; its rest is derived by the shared ratio rather than
            // matching work 1:1 as it used to.
            let work = config.blockDurations[position.blockIndex]
            return isRest ? Self.restSeconds(forWork: work) : work

        case .standard, .addOn, .addOnTakeAway:
            // Ladder styles vary which exercises run, not how long they run for.
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
