// WorkoutPlanClock.swift
// The routine plan and clock anchor the iPhone and Apple Watch share, and the pure logic that
// turns them into "which exercise, how many seconds left".
//
// Why this exists: the Watch used to learn the current exercise only from snapshots the iPhone
// pushed on every transition, so a dropped message left it stuck on the previous exercise at 0.
// Now the iPhone sends the whole plan once (every slot and its duration) plus a clock anchor — a
// reference moment and where in the plan it falls. Each device derives the current slot from
// the plan, the anchor and its own clock, so a lost message only delays a correction; it never
// freezes the Watch.
//
// Both devices can change the anchor (Pause, Resume, Skip). Every anchor names the plan it
// belongs to and carries the time it was made; the newer one wins, and an anchor for a plan
// that isn't the current one is ignored.

import Foundation

// MARK: - Plan

/// One entry in the routine: an exercise or a rest, with its duration already worked out by the
/// iPhone (so custom timers, pyramids and blocks are baked in and the Watch needs no timing logic).
nonisolated struct PlanSlot: Codable, Equatable, Sendable {
    var name: String
    var isRest: Bool
    /// Seconds.
    var duration: Int
    /// e.g. "Left Side" for single-sided stretches.
    var sideLabel: String? = nil
    /// Which item of the routine this slot belongs to, for the "N of M" progress line. Left nil,
    /// each slot counts as its own item. A stretch session sets it so a stretch's two sides and
    /// the "Get Ready" slot before it all count as one stretch.
    var groupIndex: Int? = nil
    /// What to show as "Next" while this slot is current, when that isn't simply the next slot's
    /// name (a stretch's "Get Ready" slot points at the stretch it leads into, and a hold points
    /// at the next stretch rather than its own second side). Only used when `hasNextName` is set.
    var nextName: String? = nil
    var hasNextName: Bool = false

    init(name: String, isRest: Bool, duration: Int, sideLabel: String? = nil,
         groupIndex: Int? = nil, nextName: String? = nil, hasNextName: Bool = false) {
        self.name = name
        self.isRest = isRest
        self.duration = duration
        self.sideLabel = sideLabel
        self.groupIndex = groupIndex
        self.nextName = nextName
        self.hasNextName = hasNextName
    }

    // Decoded leniently so a plan from a build that predates the optional fields still reads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        isRest = try c.decode(Bool.self, forKey: .isRest)
        duration = try c.decode(Int.self, forKey: .duration)
        sideLabel = try c.decodeIfPresent(String.self, forKey: .sideLabel)
        groupIndex = try c.decodeIfPresent(Int.self, forKey: .groupIndex)
        nextName = try c.decodeIfPresent(String.self, forKey: .nextName)
        hasNextName = try c.decodeIfPresent(Bool.self, forKey: .hasNextName) ?? false
    }
}

nonisolated struct WorkoutPlan: Codable, Equatable, Sendable {
    /// Identifies this run of the routine. Anchors for any other plan are stale.
    var id: String
    /// When the plan was made — lets a device that has two plans in flight keep the newer.
    var createdAt: TimeInterval
    var slots: [PlanSlot]
    /// `HKWorkoutActivityType` raw value the Watch should record the session as.
    var activityTypeRaw: UInt? = nil
    /// Number of items for the "N of M" progress line when slots are grouped (see
    /// `PlanSlot.groupIndex`). Nil means one item per slot.
    var groupCount: Int? = nil
}

/// A plan together with the anchor it starts from — what the iPhone sends when a workout starts
/// and mirrors in the application context for a Watch that wakes up late.
nonisolated struct PlanSync: Codable, Equatable, Sendable {
    var plan: WorkoutPlan
    var anchor: ClockAnchor
}

// MARK: - Anchor

nonisolated struct ClockAnchor: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case phone
        case watch
    }

    /// The plan this anchor belongs to.
    var planID: String
    /// The slot that was current at `anchorDate`.
    var slotIndex: Int
    /// How far into that slot we were at `anchorDate`.
    var secondsIntoSlot: Double
    /// The moment (seconds since 1970) this anchor describes.
    var anchorDate: TimeInterval
    /// False while paused: time stops advancing from the anchor.
    var isRunning: Bool
    /// When this anchor was made. The newer anchor wins.
    var updatedAt: TimeInterval
    /// Who made it; breaks an exact tie in the phone's favour.
    var source: Source

    /// Whether this anchor should replace `other` — same plan, and newer (a tie goes to the phone,
    /// so both devices settle on the same one).
    func supersedes(_ other: ClockAnchor) -> Bool {
        guard planID == other.planID else { return false }
        if updatedAt != other.updatedAt { return updatedAt > other.updatedAt }
        return source == .phone && other.source == .watch
    }
}

// MARK: - Position

nonisolated struct PlanPosition: Equatable, Sendable {
    /// Index of the current slot. Equals the slot count once the plan is finished.
    var slotIndex: Int
    var secondsIntoSlot: Double
    /// Whole seconds left in the slot (rounded up, so a fresh 20 s slot reads 20).
    var remaining: Int
    var isRunning: Bool
    /// The plan has run out of slots. The Watch shows "Finishing…" from here until the iPhone
    /// confirms the workout is over.
    var isFinished: Bool
}

extension WorkoutPlan {
    /// Combined length of every slot, in seconds.
    var totalSeconds: Int { slots.reduce(0) { $0 + max(0, $1.duration) } }

    /// The "N" and "M" of the progress line for a slot (both one-based/total).
    func progress(forSlot index: Int) -> (item: Int, total: Int) {
        let slot = slots.indices.contains(index) ? slots[index] : nil
        return ((slot?.groupIndex ?? index) + 1, groupCount ?? slots.count)
    }

    /// What to show as "Next" while `index` is current.
    func nextName(afterSlot index: Int) -> String? {
        if slots.indices.contains(index), slots[index].hasNextName { return slots[index].nextName }
        return index + 1 < slots.count ? slots[index + 1].name : nil
    }
}

nonisolated enum PlanClock {

    /// Where the plan stands at `now`.
    static func position(plan: WorkoutPlan, anchor: ClockAnchor, at now: TimeInterval) -> PlanPosition {
        let count = plan.slots.count
        var index = min(max(anchor.slotIndex, 0), count)
        guard index < count else {
            return PlanPosition(slotIndex: count, secondsIntoSlot: 0, remaining: 0, isRunning: anchor.isRunning, isFinished: true)
        }

        var elapsed = max(0, anchor.secondsIntoSlot)
        if anchor.isRunning { elapsed += max(0, now - anchor.anchorDate) }

        while index < count, elapsed >= Double(max(0, plan.slots[index].duration)) {
            elapsed -= Double(max(0, plan.slots[index].duration))
            index += 1
        }
        guard index < count else {
            return PlanPosition(slotIndex: count, secondsIntoSlot: 0, remaining: 0, isRunning: anchor.isRunning, isFinished: true)
        }
        let remaining = max(0, Int((Double(plan.slots[index].duration) - elapsed).rounded(.up)))
        return PlanPosition(slotIndex: index, secondsIntoSlot: elapsed, remaining: remaining, isRunning: anchor.isRunning, isFinished: false)
    }

    /// The anchor for a plan that starts running at slot 0.
    static func startAnchor(planID: String, now: TimeInterval, source: ClockAnchor.Source) -> ClockAnchor {
        ClockAnchor(planID: planID, slotIndex: 0, secondsIntoSlot: 0, anchorDate: now, isRunning: true, updatedAt: now, source: source)
    }

    /// An anchor placed at an explicit slot and offset — used by the iPhone, whose own timer is the
    /// authority for what it is showing at the moment it makes an anchor.
    static func anchor(planID: String, slotIndex: Int, secondsIntoSlot: Double, isRunning: Bool,
                       now: TimeInterval, source: ClockAnchor.Source) -> ClockAnchor {
        ClockAnchor(planID: planID, slotIndex: slotIndex, secondsIntoSlot: secondsIntoSlot, anchorDate: now,
                    isRunning: isRunning, updatedAt: now, source: source)
    }

    /// Freezes the plan where it is at `now`.
    static func paused(_ plan: WorkoutPlan, _ anchor: ClockAnchor, at now: TimeInterval, by source: ClockAnchor.Source) -> ClockAnchor {
        let p = position(plan: plan, anchor: anchor, at: now)
        return ClockAnchor(planID: anchor.planID, slotIndex: p.slotIndex, secondsIntoSlot: p.secondsIntoSlot,
                           anchorDate: now, isRunning: false, updatedAt: now, source: source)
    }

    /// Lets a paused plan run again from where it stopped.
    static func resumed(_ plan: WorkoutPlan, _ anchor: ClockAnchor, at now: TimeInterval, by source: ClockAnchor.Source) -> ClockAnchor {
        let p = position(plan: plan, anchor: anchor, at: now)
        return ClockAnchor(planID: anchor.planID, slotIndex: p.slotIndex, secondsIntoSlot: p.secondsIntoSlot,
                           anchorDate: now, isRunning: true, updatedAt: now, source: source)
    }

    /// Jumps to the start of the next slot, keeping the running/paused state. Skipping the last
    /// slot lands on the end of the plan.
    static func skipped(_ plan: WorkoutPlan, _ anchor: ClockAnchor, at now: TimeInterval, by source: ClockAnchor.Source) -> ClockAnchor {
        let p = position(plan: plan, anchor: anchor, at: now)
        return ClockAnchor(planID: anchor.planID, slotIndex: min(p.slotIndex + 1, plan.slots.count), secondsIntoSlot: 0,
                           anchorDate: now, isRunning: anchor.isRunning, updatedAt: now, source: source)
    }

    /// Whether an incoming plan should replace the one a device holds: any plan if it has none,
    /// otherwise only a newer one. The same plan arriving again changes nothing.
    static func shouldAdopt(_ incoming: WorkoutPlan, over current: WorkoutPlan?) -> Bool {
        guard let current else { return true }
        guard incoming.id != current.id else { return false }
        return incoming.createdAt >= current.createdAt
    }
}
