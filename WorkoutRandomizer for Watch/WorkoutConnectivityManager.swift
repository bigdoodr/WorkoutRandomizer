// WorkoutConnectivityManager.swift (watchOS)
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
}

class WorkoutConnectivityManager: NSObject, ObservableObject {
    static let shared = WorkoutConnectivityManager()

    @Published var workoutState: WorkoutState?
    @Published var isWatchConnected = false
    /// Set to true when a new workout state arrives and fitness tracking hasn't started yet
    @Published var shouldPromptToStartTracking = false
    /// Set to true when iPhone sends a prepareToStart signal; shows Start button on watch
    @Published var isReadyToStart = false
    /// Non-nil when the iPhone signals natural workout completion; drives the watch recap screen
    @Published var completedSummary: WatchCompletedSummary?

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

    private override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func sendRequestStart() {
        guard let session = session, session.isReachable else { return }
        isReadyToStart = false
        let message: [String: Any] = ["type": "requestStart"]
        session.sendMessage(message, replyHandler: nil)
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
            if let data = context["workoutStatePayload"] as? Data {
                DispatchQueue.main.async {
                    self.decodeAndApplyState(data)
                }
            }
        }
    }

    // MARK: Receive application context (delivered on wake / app launch)

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        if let data = applicationContext["workoutStatePayload"] as? Data {
            DispatchQueue.main.async {
                self.decodeAndApplyState(data)
            }
        } else {
            // Empty context means workout was stopped on the phone
            DispatchQueue.main.async {
                self.workoutState = nil
            }
        }
    }

    // MARK: Receive live messages

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        guard let type = message["type"] as? String else { return }

        DispatchQueue.main.async {
            switch type {

            // --- Workout state (full snapshot) ---
            case "workoutState":
                if let data = message["payload"] as? Data {
                    self.decodeAndApplyState(data)
                }

            // --- Timer tick ---
            case "timerUpdate":
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
                    self.handleControl(control)
                }

            // --- Natural workout/stretch completion ---
            case "workoutCompleted":
                let count = message["count"] as? Int ?? 0
                let totalSeconds = message["totalSeconds"] as? Int ?? 0
                let label = message["label"] as? String ?? "Workout"
                self.completedSummary = WatchCompletedSummary(count: count, totalSeconds: totalSeconds, label: label)
                self.workoutState = nil
                WorkoutSessionManager.shared.endWorkout()

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
            // Prompt to start fitness tracking when a workout first appears
            // and the HealthKit session isn't already running
            if wasNil && state.isPlaying && !WorkoutSessionManager.shared.isWorkoutActive {
                self.shouldPromptToStartTracking = true
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
                isPaused: state.isPaused
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
        isReadyToStart = false
    }

    private func handleControl(_ control: ControlMessage) {
        switch control {
        case .workoutPaused:
            WorkoutSessionManager.shared.pauseWorkout()
        case .workoutResumed:
            WorkoutSessionManager.shared.resumeWorkout()
        case .workoutStopped:
            WorkoutSessionManager.shared.endWorkout()
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
