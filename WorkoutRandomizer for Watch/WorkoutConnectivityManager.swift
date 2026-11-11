// WorkoutConnectivityManager.swift (watchOS)
// Receives WatchConnectivity messages from the iOS app and drives the Watch UI

#if os(watchOS)
import Combine
import Foundation
import UserNotifications
import WatchConnectivity
import WatchKit
import os

// MARK: - watchOS-specific WorkoutConnectivityManager

struct WatchCompletedSummary {
    let count: Int
    let totalSeconds: Int
    let label: String
    // Captured from the watch's own HealthKit session at completion time
    var peakHeartRate: Double = 0
    var activeCalories: Double = 0
    var hrZoneDurations: [(name: String, seconds: TimeInterval)] = []
}

class WorkoutConnectivityManager: NSObject, ObservableObject {
    static let shared = WorkoutConnectivityManager()

    @Published var workoutState: WorkoutState?
    @Published var isWatchConnected = false
    /// Set to true when a new workout state arrives and fitness tracking hasn't started yet
    @Published var shouldPromptToStartTracking = false
    /// Set to true when iPhone sends a prepareToStart signal; shows Start button on watch
    @Published var isReadyToStart = false
    /// True after the user taps Start on the watch, until the first workout state
    /// arrives from the iPhone. Drives the "Starting…" screen instead of falling
    /// back to "No Active Workout".
    @Published var isAwaitingSessionStart = false
    /// Non-nil when the iPhone signals natural workout completion; drives the watch recap screen
    @Published var completedSummary: WatchCompletedSummary?

    // MARK: Plan + clock anchor
    // The iPhone sends the whole routine once, plus an anchor. While both are held the watch works
    // out the current exercise from them and its own clock; the per-transition snapshots become
    // a fallback for sessions that don't send a plan.

    /// The routine the watch is following, if the iPhone sent one.
    private(set) var plan: WorkoutPlan?
    /// Where the plan stood at a reference moment; replaced by whichever device acts last.
    private(set) var anchor: ClockAnchor?
    /// The plan has run out of slots but the iPhone hasn't confirmed the workout is over yet.
    @Published var isFinishing = false
    private var planTicker: Timer?

    // MARK: Clock offset
    // Plan and anchor times are in the iPhone's clock. The two devices' clocks can differ by a
    // second or two, which would make this side count down early or late by that much. A
    // round-trip ping measures it: ask the phone for its clock, and compare against the midpoint
    // of the round trip. Delivery latency cancels out (it would otherwise look like skew); what's
    // left is at most half the round trip, so a difference is only acted on once it clearly
    // exceeds that.
    private static let timingLog = Logger(subsystem: "rocks.scruggsfam.productions.WorkoutRandomizer", category: "Timing")
    private struct ClockSample { let offset: TimeInterval; let roundTrip: TimeInterval }
    private var clockSamples: [ClockSample] = []
    private var lastClockPingAt: Date = .distantPast
    /// Watch clock minus iPhone clock, in seconds. Zero until a measurement shows a real difference.
    private(set) var clockOffset: TimeInterval = 0

    /// "Now" in the iPhone's clock.
    private func phoneNow() -> TimeInterval {
        Date().timeIntervalSince1970 - clockOffset
    }

    /// One round-trip measurement. Needs the phone reachable; quietly does nothing otherwise.
    private func pingPhoneClock() {
        lastClockPingAt = Date()
        guard let session, session.isReachable else { return }
        let sentAt = Date().timeIntervalSince1970
        session.sendMessage(["type": "clockPing"], replyHandler: { [weak self] reply in
            let receivedAt = Date().timeIntervalSince1970
            guard let phoneTime = reply["phoneTime"] as? TimeInterval else { return }
            DispatchQueue.main.async {
                self?.recordClockSample(sentAt: sentAt, phoneTime: phoneTime, receivedAt: receivedAt)
            }
        }, errorHandler: nil)
    }

    /// A short burst when a plan starts (so the first exercise is right), then one now and then.
    private func pingPhoneClockBurst() {
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 * Double(i)) { [weak self] in
                self?.pingPhoneClock()
            }
        }
    }

    private func recordClockSample(sentAt: TimeInterval, phoneTime: TimeInterval, receivedAt: TimeInterval) {
        let roundTrip = receivedAt - sentAt
        guard roundTrip > 0, roundTrip < 5 else { return }
        clockSamples.append(ClockSample(offset: (sentAt + receivedAt) / 2 - phoneTime, roundTrip: roundTrip))
        if clockSamples.count > 8 { clockSamples.removeFirst() }
        // The quickest round trip is the most trustworthy.
        guard let best = clockSamples.min(by: { $0.roundTrip < $1.roundTrip }) else { return }
        let applied = abs(best.offset) > best.roundTrip / 2 + 0.25 ? best.offset : 0
        Self.timingLog.notice("Clock vs iPhone: offset \(best.offset, format: .fixed(precision: 3)) s, round trip \(best.roundTrip, format: .fixed(precision: 3)) s, applied \(applied, format: .fixed(precision: 3)) s")
        guard abs(applied - clockOffset) > 0.05 else { return }
        clockOffset = applied
        recomputeFromPlan()
    }

    /// Whether the current exercise is being derived from a plan (true) or taken from snapshots.
    var usesPlan: Bool { plan != nil && anchor != nil }

    /// Timestamp (epoch seconds) of the most recent event applied to the UI.
    /// Used to discard stale application contexts delivered late by the system —
    /// the cause of the watch dropping back to "No Active Workout" mid-session.
    private var lastEventAt: TimeInterval = 0
    /// Absolute moment the current exercise or rest ends, as told by the phone. The watch
    /// counts down to this rather than trusting whatever number last arrived, so link latency
    /// no longer accumulates into visible drift. Nil when the phone is on an older build that
    /// doesn't send one.
    @Published var slotDeadline: Date?
    /// Send-time of the most recently applied timer tick, used to drop out-of-order deliveries —
    /// without it a late message can bump the countdown back up.
    private var lastTimerSentAt: TimeInterval = 0
    /// Timestamp of the last handled completion. Completions can arrive multiple
    /// times (live message, application context, and inside later sessionEnded
    /// contexts) — this de-duplicates them. Persisted so a relaunch doesn't
    /// resurface an already-dismissed recap.
    private var lastHandledCompletionAt: TimeInterval =
        UserDefaults.standard.double(forKey: "lastHandledCompletionAt") {
        didSet {
            UserDefaults.standard.set(lastHandledCompletionAt, forKey: "lastHandledCompletionAt")
        }
    }

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

    private override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func sendRequestStart() {
        guard let session = session, session.isReachable else { return }
        isReadyToStart = false
        isAwaitingSessionStart = true
        let message: [String: Any] = ["type": "requestStart"]
        session.sendMessage(message, replyHandler: nil) { [weak self] error in
            print("Failed to send requestStart: \(error.localizedDescription)")
            DispatchQueue.main.async {
                // Fall back to the ready screen so the user can retry
                self?.isAwaitingSessionStart = false
                self?.isReadyToStart = true
            }
        }
    }

    func sendRequestStop() {
        guard let session = session, session.isReachable else { return }
        session.sendMessage(["type": "requestStop"], replyHandler: nil) { error in
            print("Failed to send requestStop: \(error.localizedDescription)")
        }
    }

    /// Asks the iPhone to toggle pause/resume on the active player. The watch doesn't
    /// decide pause vs. resume itself — it just relays the tap, and the phone (the source
    /// of truth for `isPlaying`/`isPaused`) flips its own state, same as tapping the
    /// button there would.
    func sendRequestPause() {
        guard let session = session, session.isReachable else { return }
        session.sendMessage(["type": "requestPause"], replyHandler: nil) { error in
            print("Failed to send requestPause: \(error.localizedDescription)")
        }
    }

    /// Asks the iPhone to skip to the next exercise/rest slot.
    func sendRequestSkip() {
        guard let session = session, session.isReachable else { return }
        session.sendMessage(["type": "requestSkip"], replyHandler: nil) { error in
            print("Failed to send requestSkip: \(error.localizedDescription)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WorkoutConnectivityManager: WCSessionDelegate {

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isWatchConnected = (activationState == .activated)
        }
        if let error {
            print("WCSession activation failed: \(error.localizedDescription)")
        }
        // Check for any pending applicationContext that was set while the watch was asleep
        if activationState == .activated {
            let context = session.receivedApplicationContext
            DispatchQueue.main.async {
                self.applyApplicationContext(context)
            }
        }
    }

    // MARK: Receive application context (delivered on wake / app launch)

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            self.applyApplicationContext(applicationContext)
        }
    }

    /// Applies an application context, ignoring anything older than the last
    /// event we already handled (contexts can be delivered late, after fresher
    /// live messages have arrived).
    private func applyApplicationContext(_ context: [String: Any]) {
        let sentAt = context["sentAt"] as? TimeInterval ?? 0
        guard sentAt >= lastEventAt else { return }

        if let data = context["planSyncPayload"] as? Data,
           let sync = try? JSONDecoder().decode(PlanSync.self, from: data) {
            applyPlanSync(sync)
        }
        if let data = context["workoutStatePayload"] as? Data {
            lastEventAt = sentAt
            decodeAndApplyState(data)
            return
        }

        // A context can carry both a completion (for a watch that slept through
        // it) and the sessionEnded marker — handle both, not either/or.
        if let completed = context["workoutCompleted"] as? [String: Any] {
            lastEventAt = sentAt
            handleWorkoutCompleted(
                count: completed["count"] as? Int ?? 0,
                totalSeconds: completed["totalSeconds"] as? Int ?? 0,
                label: completed["label"] as? String ?? "Workout",
                completedAt: completed["completedAt"] as? TimeInterval ?? sentAt
            )
        }
        if context["sessionEnded"] as? Bool == true {
            lastEventAt = sentAt
            // Session ended on the phone. Keep a completion recap if one is showing.
            clearPlan()
            if completedSummary == nil {
                workoutState = nil
            }
            isReadyToStart = false
            isAwaitingSessionStart = false
            WorkoutSessionManager.shared.clearPreparedConfiguration()
        }
        // Empty/unknown contexts are ignored — they carry no information and
        // clearing state on them caused spurious "No Active Workout" screens.
    }

    /// Central completion handler used by all delivery paths (live message and
    /// application context). De-duplicates on the completion's own timestamp.
    private func handleWorkoutCompleted(count: Int, totalSeconds: Int, label: String, completedAt: TimeInterval) {
        guard completedAt > lastHandledCompletionAt else { return }
        lastHandledCompletionAt = completedAt
        lastEventAt = max(lastEventAt, completedAt)

        // Capture health metrics and zone data before ending the session
        let sessionManager = WorkoutSessionManager.shared
        let zones = sessionManager.captureCurrentHRZones()
        completedSummary = WatchCompletedSummary(
            count: count,
            totalSeconds: totalSeconds,
            label: label,
            peakHeartRate: sessionManager.peakHeartRate,
            activeCalories: sessionManager.activeCalories,
            hrZoneDurations: zones
        )
        clearPlan()   // the iPhone has confirmed the workout is over
        workoutState = nil
        isReadyToStart = false
        isAwaitingSessionStart = false
        sessionManager.endWorkout()
        sessionManager.clearPreparedConfiguration()

        // Relay zone data to iPhone so it can appear in the iOS recap
        sendZoneDataToPhone(zones)
    }

    private func sendZoneDataToPhone(_ zones: [(name: String, seconds: TimeInterval)]) {
        guard let session = session, !zones.isEmpty else { return }
        // transferUserInfo queues reliably and delivers even when the phone isn't
        // currently reachable — unlike sendMessage which silently drops the data
        // if the phone isn't in the foreground at the moment the workout ends.
        let payload = zones.map { ["name": $0.name, "seconds": $0.seconds] as [String: Any] }
        session.transferUserInfo(["type": "zoneData", "zones": payload])
    }

    // MARK: Plan and anchor handling

    /// A plan (and its anchor) from the iPhone. A new plan replaces the current one only if it's
    /// newer; the same plan again just offers its anchor, which has to be newer to be used.
    private func applyPlanSync(_ sync: PlanSync) {
        if PlanClock.shouldAdopt(sync.plan, over: plan) {
            plan = sync.plan
            anchor = sync.anchor
            isFinishing = false
            pingPhoneClockBurst()
        } else if let plan, plan.id == sync.plan.id, let current = anchor, sync.anchor.supersedes(current) {
            anchor = sync.anchor
        } else {
            return   // a stale plan, or one we already have
        }
        startPlanTicker()
        recomputeFromPlan()
    }

    /// An anchor from the iPhone. Ignored if it's for another plan or older than the one we hold.
    private func applyAnchor(_ incoming: ClockAnchor) {
        guard let plan, incoming.planID == plan.id, let current = anchor, incoming.supersedes(current) else { return }
        let runStateChanged = incoming.isRunning != current.isRunning
        anchor = incoming
        // Keep the HealthKit session's pause state in step. The iPhone's control message does the
        // same; pausing an already-paused session is harmless, and this covers that message
        // being lost.
        if runStateChanged {
            if incoming.isRunning { WorkoutSessionManager.shared.resumeWorkout() } else { WorkoutSessionManager.shared.pauseWorkout() }
        }
        startPlanTicker()
        recomputeFromPlan()
    }

    /// Pause / Resume from the wrist. Takes effect on the watch immediately and is sent to the
    /// iPhone as a new anchor; whichever side acted last wins.
    func localTogglePause() {
        guard let plan, let current = anchor else { return }
        let now = phoneNow()
        let next = current.isRunning
            ? PlanClock.paused(plan, current, at: now, by: .watch)
            : PlanClock.resumed(plan, current, at: now, by: .watch)
        if next.isRunning { WorkoutSessionManager.shared.resumeWorkout() } else { WorkoutSessionManager.shared.pauseWorkout() }
        commitLocal(next)
    }

    /// Skip from the wrist: jumps to the next slot here at once and tells the iPhone.
    func localSkip() {
        guard let plan, let current = anchor else { return }
        let next = PlanClock.skipped(plan, current, at: phoneNow(), by: .watch)
        triggerWatchFeedback(.start)
        commitLocal(next)
    }

    private func commitLocal(_ next: ClockAnchor) {
        anchor = next
        startPlanTicker()
        recomputeFromPlan()
        sendAnchorToPhone(next)
    }

    /// Always mirrored in the application context (the latest wins and arrives once the phone is
    /// reachable), and sent live as well when it is reachable now.
    private func sendAnchorToPhone(_ anchor: ClockAnchor) {
        guard let session = session, let data = try? JSONEncoder().encode(anchor) else { return }
        try? session.updateApplicationContext(["anchorPayload": data, "sentAt": anchor.updatedAt])
        guard session.isReachable else { return }
        session.sendMessage(["type": "anchor", "payload": data, "sentAt": anchor.updatedAt], replyHandler: nil) { error in
            print("Failed to send anchor: \(error.localizedDescription)")
        }
    }

    /// Derives the current exercise and countdown from the plan and anchor. When the plan has run
    /// out it switches to "Finishing…" and waits for the iPhone to confirm.
    private func recomputeFromPlan() {
        guard let plan, let anchor, completedSummary == nil else { return }
        let now = phoneNow()
        let position = PlanClock.position(plan: plan, anchor: anchor, at: now)

        if position.isFinished {
            if !isFinishing { isFinishing = true }
            slotDeadline = nil
            stopPlanTicker()
            return
        }
        if isFinishing { isFinishing = false }

        let slot = plan.slots[position.slotIndex]
        let next = position.slotIndex + 1 < plan.slots.count ? plan.slots[position.slotIndex + 1].name : nil
        let current = workoutState
        if current?.currentIndex != position.slotIndex
            || current?.timeRemaining != position.remaining
            || current?.isPaused != !anchor.isRunning
            || current?.currentExerciseName != slot.name
            || current?.isPlaying != true {
            workoutState = WorkoutState(
                currentExerciseName: slot.name,
                currentIndex: position.slotIndex,
                totalExercises: plan.slots.count,
                timeRemaining: position.remaining,
                isRest: slot.isRest,
                nextExerciseName: next,
                isPlaying: true,
                isPaused: !anchor.isRunning,
                sideLabel: slot.sideLabel,
                activityTypeRaw: plan.activityTypeRaw
            )
        }

        // The countdown target the view counts down to. Stable between ticks (only a real change
        // of more than half a second moves it) so the view isn't re-synced every tick.
        if anchor.isRunning {
            let deadline = Date(timeIntervalSinceNow: Double(position.remaining))
            if let existing = slotDeadline, abs(existing.timeIntervalSince(deadline)) < 0.6 {
                // keep
            } else {
                slotDeadline = deadline
            }
        } else if slotDeadline != nil {
            slotDeadline = nil
        }

        // A real state has arrived — the handoff / starting screens are done.
        if isReadyToStart { isReadyToStart = false }
        if isAwaitingSessionStart { isAwaitingSessionStart = false }
    }

    private func startPlanTicker() {
        guard planTicker == nil else { return }
        // In the common modes so it keeps running while the view is being interacted with.
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.recomputeFromPlan()
            if Date().timeIntervalSince(self.lastClockPingAt) > 60 { self.pingPhoneClock() }
        }
        RunLoop.main.add(timer, forMode: .common)
        planTicker = timer
    }

    private func stopPlanTicker() {
        planTicker?.invalidate()
        planTicker = nil
    }

    /// The workout is over or stopped: forget the plan.
    private func clearPlan() {
        stopPlanTicker()
        plan = nil
        anchor = nil
        isFinishing = false
    }

    // MARK: Receive live messages

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        guard let type = message["type"] as? String else { return }
        let sentAt = message["sentAt"] as? TimeInterval ?? Date().timeIntervalSince1970

        DispatchQueue.main.async {
            switch type {

            // --- Workout state (full snapshot) ---
            case "workoutState":
                if let data = message["payload"] as? Data {
                    self.lastEventAt = max(self.lastEventAt, sentAt)
                    // A transition resets the slot, so its deadline always wins — unless a plan
                    // is driving the countdown, in which case the plan is the source.
                    self.lastTimerSentAt = sentAt
                    if !self.usesPlan {
                        self.slotDeadline = (message["deadline"] as? TimeInterval)
                            .map { Date(timeIntervalSince1970: $0) }
                    }
                    self.decodeAndApplyState(data)
                }

            // --- Timer tick ---
            case "timerUpdate":
                // With a plan the watch derives the countdown itself; ticks are ignored.
                guard !self.usesPlan else { return }
                // Messages can arrive out of order; an older tick must not win.
                guard sentAt >= self.lastTimerSentAt else { return }
                self.lastTimerSentAt = sentAt
                if let deadline = message["deadline"] as? TimeInterval {
                    self.slotDeadline = Date(timeIntervalSince1970: deadline)
                }
                if let time = message["timeRemaining"] as? Int {
                    self.applyTimerUpdate(time)
                }

            // --- Plan and clock anchor ---
            case "planSync":
                if let data = message["payload"] as? Data,
                   let sync = try? JSONDecoder().decode(PlanSync.self, from: data) {
                    self.applyPlanSync(sync)
                }
            case "anchor":
                if let data = message["payload"] as? Data,
                   let anchor = try? JSONDecoder().decode(ClockAnchor.self, from: data) {
                    self.applyAnchor(anchor)
                }

            // --- Haptic/audio feedback ---
            case "feedback":
                if let eventString = message["event"] as? String,
                   let event = FeedbackType(rawValue: eventString) {
                    self.triggerWatchFeedback(event)
                }

            // --- Control messages (pause / resume / stop) ---
            case "control":
                if let controlString = message["message"] as? String,
                   let control = ControlMessage(rawValue: controlString) {
                    self.lastEventAt = max(self.lastEventAt, sentAt)
                    self.handleControl(control)
                }

            // --- Natural workout/stretch completion ---
            case "workoutCompleted":
                self.handleWorkoutCompleted(
                    count: message["count"] as? Int ?? 0,
                    totalSeconds: message["totalSeconds"] as? Int ?? 0,
                    label: message["label"] as? String ?? "Workout",
                    completedAt: message["completedAt"] as? TimeInterval ?? sentAt
                )

            // --- Handoff: iPhone ready for watch to start ---
            case "prepareToStart":
                if let raw = message["activityTypeRaw"] as? UInt {
                    WorkoutSessionManager.shared.declareActivityType(raw)
                }
                self.isReadyToStart = true

            default:
                break
            }
        }
    }

    // Queued delivery when watch app was not in foreground
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        guard let type = userInfo["type"] as? String, type == "prepareToStart" else { return }
        let declared = userInfo["activityTypeRaw"] as? UInt
        DispatchQueue.main.async {
            if let declared {
                WorkoutSessionManager.shared.declareActivityType(declared)
            }
            self.isReadyToStart = true
            // When the app is backgrounded, surface it via a local notification so the
            // user sees a banner on the watch face and can tap directly into the ready screen.
            if WKApplication.shared().applicationState == .background {
                self.postPrepareToStartNotification()
            }
        }
    }

    private func postPrepareToStartNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Ready to Start"
        content.body = "Open to begin your workout on Apple Watch."
        content.sound = .default
        content.userInfo = ["action": "prepareToStart"]

        let request = UNNotificationRequest(
            identifier: "prepareToStart",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Helpers

    private func decodeAndApplyState(_ data: Data) {
        do {
            let state = try JSONDecoder().decode(WorkoutState.self, from: data)
            let wasNil = self.workoutState == nil
            self.workoutState = state
            // A real state arrived — the handoff/starting screens are done
            self.isReadyToStart = false
            self.isAwaitingSessionStart = false
            let sessionManager = WorkoutSessionManager.shared
            if let raw = state.activityTypeRaw {
                sessionManager.declareActivityType(raw)
            }
            if state.isPlaying && !sessionManager.isWorkoutActive,
               sessionManager.preparedConfiguration != nil {
                // The iPhone already declared this session via startWatchApp
                // (handle(_:) stored the configuration) — start tracking silently,
                // no prompt needed. The manager picks the type: the one declared in this
                // state first, then the stashed handoff config.
                Task {
                    await sessionManager.startWorkout()
                }
            } else if wasNil && state.isPlaying && !sessionManager.isWorkoutActive {
                // No prepared configuration — the auto-launch may still be in
                // flight, so give it a moment before prompting. This avoids a
                // spurious alert racing the auto-start.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if self.workoutState != nil,
                       self.completedSummary == nil,
                       !WorkoutSessionManager.shared.isWorkoutActive {
                        self.shouldPromptToStartTracking = true
                    }
                }
            }
            // A plan, when there is one, is the source for the current exercise.
            if usesPlan { recomputeFromPlan() }
        } catch {
            print("Failed to decode workout state: \(error.localizedDescription)")
        }
    }

    private func applyTimerUpdate(_ time: Int) {
        // Don't resurrect a state after natural completion — prevents the "0 timer" stuck screen
        guard completedSummary == nil else { return }

        if let state = self.workoutState {
            self.workoutState = WorkoutState(
                currentExerciseName: state.currentExerciseName,
                currentIndex: state.currentIndex,
                totalExercises: state.totalExercises,
                timeRemaining: time,
                isRest: state.isRest,
                nextExerciseName: state.nextExerciseName,
                isPlaying: state.isPlaying,
                isPaused: state.isPaused,
                sideLabel: state.sideLabel,
                activityTypeRaw: state.activityTypeRaw
            )
        } else {
            // Minimal placeholder so the timer is visible before a full state arrives
            self.workoutState = WorkoutState(
                currentExerciseName: "Workout",
                currentIndex: 0,
                totalExercises: 0,
                timeRemaining: time,
                isRest: false,
                nextExerciseName: nil,
                isPlaying: true,
                isPaused: false
            )
        }
    }

    func dismissCompleted() {
        completedSummary = nil
        // Do NOT reset isReadyToStart here — a prepareToStart for the next routine
        // may have already arrived while the recap was visible. Clearing it would
        // drop the watch to "No Active Workout" instead of showing "Start Workout".
        isAwaitingSessionStart = false
    }

    private func handleControl(_ control: ControlMessage) {
        switch control {
        case .workoutPaused:
            WorkoutSessionManager.shared.pauseWorkout()
        case .workoutResumed:
            WorkoutSessionManager.shared.resumeWorkout()
        case .workoutStopped:
            WorkoutSessionManager.shared.endWorkout()
            WorkoutSessionManager.shared.clearPreparedConfiguration()
            isReadyToStart = false
            isAwaitingSessionStart = false
            clearPlan()
            // Only clear workout state for manual stops; natural completion already set completedSummary
            if completedSummary == nil {
                self.workoutState = nil
            }
        }
    }

    private func triggerWatchFeedback(_ event: FeedbackType) {
        let device = WKInterfaceDevice.current()
        switch event {
        case .start:         device.play(.start)
        case .warning:       device.play(.notification)
        case .end:           device.play(.stop)
        case .complete:      device.play(.success)
        case .enterActive:   device.play(.directionUp)
        case .enterCoolDown: device.play(.directionDown)
        }
    }
}

#endif
