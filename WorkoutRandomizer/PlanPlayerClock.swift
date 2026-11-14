//  PlanPlayerClock.swift
//  Bodyweight WorkoutRandomizer
//
//  The clock behind a workout player: a plan (every slot and its duration) plus an anchor (where
//  the plan stood at a reference moment), with the current slot and countdown *derived* from them
//  and the device's clock — the same `PlanClock` math the Apple Watch uses. A late or stalled
//  timer therefore costs nothing: the next tick just looks at the time.
//
//  A player owns one of these, builds a plan from its own routine, and reacts through callbacks
//  (play a cue, swap the video, update its counters). The engine handles what every player shares:
//   • stamping the anchor when the clock starts,
//   • advancing through slots as time passes,
//   • Pause / Resume / Skip, each of which re-anchors and tells the Watch,
//   • adopting a newer anchor made on the Watch,
//   • finishing exactly once.
//
//  It doesn't draw anything. The stretch and saved-routine players use it; the main workout
//  player has its own inline copy of the same logic (see WorkoutPlayerView.clockTick).

import Foundation

@MainActor
final class PlanPlayerClock {

    /// Why the current slot changed.
    enum Reason {
        /// The clock ran out of time in the slot.
        case natural
        /// Skip, tapped here.
        case skipped
        /// A newer anchor from the Watch (its Skip, or catching up).
        case watch
    }

    /// How the engine tells the Watch about the plan. Absent in tests and off iOS.
    struct Link {
        var begin: (PlanSync) -> Void
        var send: (ClockAnchor) -> Void
    }

    // MARK: Callbacks

    /// Whole seconds have gone by in `slot` (counted for stats; also called with the remainder of
    /// a slot being left).
    var onElapsed: (_ slot: Int, _ seconds: Int) -> Void = { _, _ in }
    /// A tick moved the countdown down; `remaining` is the new whole-seconds value.
    var onSecond: (_ remaining: Int) -> Void = { _ in }
    /// The countdown reached 3.
    var onWarning: () -> Void = {}
    /// The player moved to another slot. `slotIndex` and `remaining` are already updated.
    var onSlotChange: (_ from: Int, _ to: Int, _ reason: Reason) -> Void = { _, _, _ in }
    /// The countdown was set directly (start, skip, a Watch anchor) rather than ticked down.
    var onReset: (_ remaining: Int) -> Void = { _ in }
    /// Paused or resumed. `byWatch` is true when the Watch did it.
    var onPauseChange: (_ paused: Bool, _ byWatch: Bool) -> Void = { _, _ in }
    /// The last slot ended (or was skipped past). `lastSlot` is that slot. Called once.
    var onFinish: (_ lastSlot: Int, _ reason: Reason) -> Void = { _, _ in }

    // MARK: State

    private(set) var plan: WorkoutPlan?
    private(set) var anchor: ClockAnchor?
    private(set) var slotIndex = 0
    /// Whole seconds left in the current slot, rounded up — what both devices show.
    private(set) var remaining = 0
    private(set) var isPaused = false
    private(set) var isActive = false

    var link: Link?
    /// The clock. Tests replace it.
    var now: () -> TimeInterval = { Date().timeIntervalSince1970 }

    private var timer: Timer?

    var currentSlot: PlanSlot? {
        guard let plan, plan.slots.indices.contains(slotIndex) else { return nil }
        return plan.slots[slotIndex]
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: Lifecycle

    /// Starts the plan at slot 0. The anchor is stamped here, immediately before the clock runs,
    /// so "slot 0, 0 s in" is the moment the first slot actually begins on this device.
    func start(plan: WorkoutPlan, usesTimer: Bool = true) {
        guard !plan.slots.isEmpty else { return }
        timer?.invalidate()
        self.plan = plan
        slotIndex = 0
        remaining = plan.slots[0].duration
        isPaused = false
        isActive = true
        let start = PlanClock.anchor(planID: plan.id, slotIndex: 0, secondsIntoSlot: 0, isRunning: true,
                                     now: now(), source: .phone)
        anchor = start
        link?.begin(PlanSync(plan: plan, anchor: start))
        onReset(remaining)
        if usesTimer { startTimer() }
    }

    /// Stops ticking. The caller sends the Watch its own stop/complete message.
    func stop() {
        timer?.invalidate()
        timer = nil
        isActive = false
    }

    /// Runs in the common run-loop modes so it keeps firing while the user scrolls the player.
    private func startTimer() {
        let newTimer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    // MARK: Ticking

    /// Brings the player in line with the clock: advances through any slots time has passed, then
    /// sets the countdown. Called by the timer; tests call it with a chosen time.
    func tick(at time: TimeInterval? = nil) {
        guard isActive, !isPaused, let plan, let anchor else { return }
        let position = PlanClock.position(plan: plan, anchor: anchor, at: time ?? now())
        let count = plan.slots.count

        // Leave any slot the clock has moved past (usually one; more after a long stall).
        let target = min(position.slotIndex, count)
        while slotIndex < target {
            onElapsed(slotIndex, remaining)            // what was left of the slot we're leaving
            let from = slotIndex
            if from + 1 >= count {
                finish(lastSlot: from, reason: .natural)
                return
            }
            slotIndex = from + 1
            remaining = plan.slots[slotIndex].duration
            onSlotChange(from, slotIndex, .natural)
        }
        guard isActive else { return }

        let newRemaining = position.remaining
        if newRemaining < remaining {
            onElapsed(slotIndex, remaining - newRemaining)
            remaining = newRemaining
            onSecond(newRemaining)
            if newRemaining == 3 { onWarning() }
        } else if newRemaining != remaining {
            remaining = newRemaining
            onReset(newRemaining)
        }
    }

    // MARK: Actions

    /// Pause or resume from this device. Re-anchors and tells the Watch. Returns the new state.
    @discardableResult
    func togglePause() -> Bool {
        guard isActive, let plan, let current = anchor else { return isPaused }
        let t = now()
        let next = isPaused
            ? PlanClock.resumed(plan, current, at: t, by: .phone)
            : PlanClock.paused(plan, current, at: t, by: .phone)
        anchor = next
        isPaused = !next.isRunning
        link?.send(next)
        onPauseChange(isPaused, false)
        return isPaused
    }

    /// Skip to the start of the next slot (or finish, from the last one).
    func skip() {
        guard isActive, let plan, let current = anchor else { return }
        let next = PlanClock.skipped(plan, current, at: now(), by: .phone)
        anchor = next
        let from = slotIndex
        if from + 1 >= plan.slots.count {
            finish(lastSlot: from, reason: .skipped)
            return
        }
        slotIndex = from + 1
        remaining = plan.slots[slotIndex].duration
        link?.send(next)
        onSlotChange(from, slotIndex, .skipped)
        onReset(remaining)
    }

    /// An anchor the Watch made (the connectivity layer has already checked it's newer and for
    /// this plan). Moves this player to match, without sending an anchor back.
    func adopt(_ incoming: ClockAnchor) {
        guard isActive, let plan, incoming.planID == plan.id else { return }
        anchor = incoming
        let position = PlanClock.position(plan: plan, anchor: incoming, at: now())
        let count = plan.slots.count

        if position.isFinished {
            // Skipped past the end: step through what's left, then finish.
            while slotIndex < count - 1 {
                let from = slotIndex
                slotIndex += 1
                remaining = plan.slots[slotIndex].duration
                onSlotChange(from, slotIndex, .watch)
            }
            finish(lastSlot: count - 1, reason: .watch)
            return
        }

        while slotIndex < position.slotIndex {
            let from = slotIndex
            slotIndex += 1
            remaining = plan.slots[slotIndex].duration
            onSlotChange(from, slotIndex, .watch)
        }
        remaining = position.remaining
        onReset(remaining)

        let shouldPause = !incoming.isRunning
        if isPaused != shouldPause {
            isPaused = shouldPause
            onPauseChange(isPaused, true)
        }
    }

    // MARK: Finishing

    private func finish(lastSlot: Int, reason: Reason) {
        guard isActive else { return }
        isActive = false
        timer?.invalidate()
        timer = nil
        remaining = 0
        slotIndex = plan?.slots.count ?? slotIndex
        onFinish(lastSlot, reason)
    }
}

#if os(iOS)
extension PlanPlayerClock.Link {
    /// Sends the plan and anchors to the paired Apple Watch through the shared connectivity manager.
    @MainActor
    static var watch: PlanPlayerClock.Link {
        PlanPlayerClock.Link(
            begin: { WorkoutConnectivityManager.shared.beginPlan($0) },
            send: { WorkoutConnectivityManager.shared.sendAnchor($0) }
        )
    }
}
#endif
