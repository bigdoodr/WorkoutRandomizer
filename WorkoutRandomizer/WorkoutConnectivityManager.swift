// WorkoutConnectivityManager.swift
// Provides a minimal cross-platform implementation used by WorkoutRandomizer

import Combine
import Foundation

public enum FeedbackType: String, Codable {
    case start
    case warning
    case end
    case complete
}

public enum ControlMessage: String, Codable {
    case workoutPaused
    case workoutResumed
    case workoutStopped
}

public struct WorkoutState: Codable {
    public let currentExerciseName: String
    public let currentIndex: Int
    public let totalExercises: Int
    public let timeRemaining: Int
    public let isRest: Bool
    public let nextExerciseName: String?
    public let isPlaying: Bool
    public let isPaused: Bool
    /// e.g. "Left Side" / "Right Side" for single-sided stretches. Optional so
    /// old payloads still decode.
    public var sideLabel: String? = nil
}

// Health metrics sent from Watch to iPhone
struct WatchHealthMetrics: Codable {
    let heartRate: Double
    let activeCalories: Double
    let isWorkoutActive: Bool
}

#if os(iOS)

// MARK: - iOS-specific WorkoutConnectivityManager

import WatchConnectivity

@MainActor
class WorkoutConnectivityManager: ObservableObject {
    static let shared = WorkoutConnectivityManager()

    @Published var isWatchConnected = false
    @Published var isWatchReachable = false
    @Published var watchRequestedStart = false
    @Published var watchRequestedStop = false
    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var isWatchWorkoutActive = false

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

    /// The most recent completion payload for the current session. Carried inside
    /// subsequent "session ended" context updates so the watch still gets the
    /// recap even if it sleeps through the completion itself. Cleared when a new
    /// session starts sending state.
    private var pendingCompletionPayload: [String: Any]? = nil

    private init() {
        if let session = session {
            session.delegate = WatchConnectivityDelegate.shared
            session.activate()
        }
    }

    // MARK: - Send workout state to Watch

    func sendWorkoutState(_ state: WorkoutState) {
        guard let session = session else { return }

        // A new/ongoing session is sending state — any previous completion is history
        pendingCompletionPayload = nil

        // Always mirror the latest state into the application context (timestamped).
        // This way, if the watch app wakes or relaunches mid-session it immediately
        // sees the current workout instead of a stale or empty context.
        sendWorkoutStateViaContext(state)

        guard session.isReachable else { return }
        do {
            let data = try JSONEncoder().encode(state)
            let message: [String: Any] = [
                "type": "workoutState",
                "payload": data,
                "sentAt": Date().timeIntervalSince1970
            ]
            session.sendMessage(message, replyHandler: nil) { error in
                print("Failed to send workout state: \(error.localizedDescription)")
            }
        } catch {
            print("Failed to encode workout state: \(error.localizedDescription)")
        }
    }

    private func sendWorkoutStateViaContext(_ state: WorkoutState) {
        guard let session = session else { return }
        do {
            let data = try JSONEncoder().encode(state)
            let context: [String: Any] = [
                "workoutStatePayload": data,
                "sentAt": Date().timeIntervalSince1970
            ]
            try session.updateApplicationContext(context)
        } catch {
            print("Failed to send workout state via context: \(error.localizedDescription)")
        }
    }

    /// Marks the session as ended in the application context. Using an explicit,
    /// timestamped sentinel (instead of an empty dictionary) lets the watch ignore
    /// stale end-markers from a *previous* session that get delivered late.
    private func markSessionEndedInContext() {
        guard let session = session else { return }
        var context: [String: Any] = [
            "sessionEnded": true,
            "sentAt": Date().timeIntervalSince1970
        ]
        // Keep the completion recap available for a watch that slept through it.
        // The watch de-duplicates on the payload's completedAt timestamp.
        if let completion = pendingCompletionPayload {
            context["workoutCompleted"] = completion
        }
        do {
            try session.updateApplicationContext(context)
        } catch {
            print("Failed to mark session ended in context: \(error.localizedDescription)")
        }
    }

    func sendTimerUpdate(timeRemaining: Int) {
        guard let session = session, session.isReachable else { return }
        let message: [String: Any] = ["type": "timerUpdate", "timeRemaining": timeRemaining]
        session.sendMessage(message, replyHandler: nil)
    }

    func sendFeedbackEvent(_ event: FeedbackType) {
        guard let session = session, session.isReachable else { return }
        let message: [String: Any] = ["type": "feedback", "event": event.rawValue]
        session.sendMessage(message, replyHandler: nil)
    }

    func sendControlMessage(_ control: ControlMessage) {
        guard let session = session else { return }

        if control == .workoutStopped {
            markSessionEndedInContext()
        }

        guard session.isReachable else { return }
        let message: [String: Any] = [
            "type": "control",
            "message": control.rawValue,
            "sentAt": Date().timeIntervalSince1970
        ]
        session.sendMessage(message, replyHandler: nil)
    }

    func sendWorkoutCompleted(count: Int, totalSeconds: Int, label: String) {
        guard let session = session else { return }
        let sentAt = Date().timeIntervalSince1970
        let payload: [String: Any] = [
            "count": count,
            "totalSeconds": totalSeconds,
            "label": label,
            "completedAt": sentAt   // stable identity for de-duplication
        ]
        pendingCompletionPayload = payload

        // Deliver the completion via the application context so it reaches the
        // watch even when it isn't reachable right now (e.g. wrist down during a
        // floor stretch). Otherwise the watch would only see a "session ended"
        // marker and show "No Active Workout" instead of the recap.
        do {
            try session.updateApplicationContext([
                "workoutCompleted": payload,
                "sentAt": sentAt
            ])
        } catch {
            print("Failed to send completion via context: \(error.localizedDescription)")
        }

        // Also send a live message for immediate delivery when reachable;
        // the watch de-duplicates using completedAt.
        guard session.isReachable else { return }
        let message: [String: Any] = [
            "type": "workoutCompleted",
            "count": count,
            "totalSeconds": totalSeconds,
            "label": label,
            "completedAt": sentAt,
            "sentAt": sentAt
        ]
        session.sendMessage(message, replyHandler: nil)
    }

    // MARK: - Watch handoff

    func sendPrepareToStart() {
        guard let session = session else { return }
        // Always use transferUserInfo — unlike sendMessage it queues reliably and
        // triggers a WKWatchConnectivityRefreshBackgroundTask on the Watch even when
        // the Watch app isn't running, letting it post a local notification to surface itself.
        session.transferUserInfo(["type": "prepareToStart"])
    }

    // MARK: - Receive health metrics from Watch

    nonisolated func receiveHealthMetrics(_ metrics: WatchHealthMetrics) {
        Task { @MainActor in
            self.heartRate = metrics.heartRate
            self.activeCalories = metrics.activeCalories
            self.isWatchWorkoutActive = metrics.isWorkoutActive
        }
    }
}

// MARK: - WCSessionDelegate (separate class to handle nonisolated callbacks)

private class WatchConnectivityDelegate: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityDelegate()

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            WorkoutConnectivityManager.shared.isWatchConnected = (activationState == .activated)
            WorkoutConnectivityManager.shared.isWatchReachable = session.isReachable
        }
        if let error {
            print("WCSession activation failed: \(error.localizedDescription)")
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            WorkoutConnectivityManager.shared.isWatchReachable = session.isReachable
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            WorkoutConnectivityManager.shared.isWatchConnected = false
        }
    }

    func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            WorkoutConnectivityManager.shared.isWatchConnected = false
        }
        session.activate()
    }

    // MARK: Receive messages from Watch

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        guard let type = message["type"] as? String else { return }

        switch type {
        case "healthMetrics":
            if let data = message["payload"] as? Data {
                do {
                    let metrics = try JSONDecoder().decode(WatchHealthMetrics.self, from: data)
                    WorkoutConnectivityManager.shared.receiveHealthMetrics(metrics)
                } catch {
                    print("Failed to decode health metrics: \(error.localizedDescription)")
                }
            }
        case "requestStart":
            Task { @MainActor in
                WorkoutConnectivityManager.shared.watchRequestedStart = true
            }
        case "requestStop":
            Task { @MainActor in
                WorkoutConnectivityManager.shared.watchRequestedStop = true
            }
        default:
            break
        }
    }
}

#else

// MARK: - Non-iOS shim so other platforms compile

final class WorkoutConnectivityManager: NSObject, ObservableObject {
    static let shared = WorkoutConnectivityManager()
    private override init() {}

    func sendWorkoutState(_ state: WorkoutState) { }
    func sendTimerUpdate(timeRemaining: Int) { }
    func sendFeedbackEvent(_ event: FeedbackType) { }
    func sendControlMessage(_ messageType: ControlMessage) { }
    func sendWorkoutCompleted(count: Int, totalSeconds: Int, label: String) { }
}

#endif

