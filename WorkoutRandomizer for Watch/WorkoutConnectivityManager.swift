// WorkoutConnectivityManager.swift (watchOS)
// WorkoutConnectivityManager.swift (watchOS)
// Receives WatchConnectivity messages from the iOS app and drives the Watch UI

#if os(watchOS)
import Combine
import Foundation
import WatchConnectivity
import WatchKit

// MARK: - watchOS-specific WorkoutConnectivityManager

class WorkoutConnectivityManager: NSObject, ObservableObject {
    static let shared = WorkoutConnectivityManager()

    @Published var workoutState: WorkoutState?
    @Published var isWatchConnected = false
    /// Set to true when a new workout state arrives and fitness tracking hasn't started yet
    @Published var shouldPromptToStartTracking = false

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

    private override init() {
        super.init()
        session?.delegate = self
        session?.activate()
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

            default:
                break
            }
        }
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

    private func handleControl(_ control: ControlMessage) {
        switch control {
        case .workoutPaused:
            WorkoutSessionManager.shared.pauseWorkout()
        case .workoutResumed:
            WorkoutSessionManager.shared.resumeWorkout()
        case .workoutStopped:
            WorkoutSessionManager.shared.endWorkout()
            self.workoutState = nil
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
