// WorkoutConnectivityManager.swift (watchOS)
// Receives WatchConnectivity messages from the iOS app and drives the Watch UI

#if os(watchOS)
import Combine
import Foundation
import UserNotifications
import WatchConnectivity
import WatchKit

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
                    // A transition resets the slot, so its deadline always wins.
                    self.lastTimerSentAt = sentAt
                    self.slotDeadline = (message["deadline"] as? TimeInterval)
                        .map { Date(timeIntervalSince1970: $0) }
                    self.decodeAndApplyState(data)
                }

            // --- Timer tick ---
            case "timerUpdate":
                // Messages can arrive out of order; an older tick must not win.
                guard sentAt >= self.lastTimerSentAt else { return }
                self.lastTimerSentAt = sentAt
                if let deadline = message["deadline"] as? TimeInterval {
                    self.slotDeadline = Date(timeIntervalSince1970: deadline)
                }
                if let time = message["timeRemaining"] as? Int {
                    self.applyTimerUpdate(time)
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
                self.isReadyToStart = true

            default:
                break
            }
        }
    }

    // Queued delivery when watch app was not in foreground
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        guard let type = userInfo["type"] as? String, type == "prepareToStart" else { return }
        DispatchQueue.main.async {
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
            if state.isPlaying && !sessionManager.isWorkoutActive,
               let config = sessionManager.preparedConfiguration {
                // The iPhone already declared this session via startWatchApp
                // (handle(_:) stored the configuration) — start tracking silently,
                // no prompt needed.
                Task {
                    await sessionManager.startWorkout(configuration: config)
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
                sideLabel: state.sideLabel
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
            // Only clear workout state for manual stops; natural completion already set completedSummary
            if completedSummary == nil {
                self.workoutState = nil
            }
        }
    }

    private func triggerWatchFeedback(_ event: FeedbackType) {
        let device = WKInterfaceDevice.current()
        switch event {
        case .start:    device.play(.start)
        case .warning:  device.play(.notification)
        case .end:      device.play(.stop)
        case .complete: device.play(.success)
        }
    }
}

#endif
