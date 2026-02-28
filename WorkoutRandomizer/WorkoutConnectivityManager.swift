// WorkoutConnectivityManager.swift
// Provides a minimal cross-platform implementation used by WorkoutRandomizer

import Foundation

#if os(iOS)
import WatchConnectivity
import HealthKit

// MARK: - Messages/Models used by iOS watch connectivity

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
}

// MARK: - iOS Implementation

final class WorkoutConnectivityManager: NSObject, ObservableObject {
    static let shared = WorkoutConnectivityManager()

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

    private override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func sendWorkoutState(_ state: WorkoutState) {
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }
        do {
            let data = try JSONEncoder().encode(state)
            let message: [String: Any] = ["type": "workoutState", "payload": data]
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        } catch {
            // Swallow encoding errors for now
        }
    }

    func sendTimerUpdate(timeRemaining: Int) {
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }
        let message: [String: Any] = ["type": "timerUpdate", "timeRemaining": timeRemaining]
        session.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    func sendFeedbackEvent(_ event: FeedbackType) {
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }
        let message: [String: Any] = ["type": "feedback", "event": event.rawValue]
        session.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    func sendControlMessage(_ messageType: ControlMessage) {
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }
        let message: [String: Any] = ["type": "control", "message": messageType.rawValue]
        session.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }
}

extension WorkoutConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // No-op
    }

    func sessionDidBecomeInactive(_ session: WCSession) { }
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}

#else

// MARK: - Non-iOS shim so other platforms compile

public enum FeedbackType: String, Codable { case start, warning, end, complete }
public enum ControlMessage: String, Codable { case workoutPaused, workoutResumed, workoutStopped }
public struct WorkoutState: Codable {
    public let currentExerciseName: String
    public let currentIndex: Int
    public let totalExercises: Int
    public let timeRemaining: Int
    public let isRest: Bool
    public let nextExerciseName: String?
    public let isPlaying: Bool
    public let isPaused: Bool
}

final class WorkoutConnectivityManager: NSObject, ObservableObject {
    static let shared = WorkoutConnectivityManager()
    private override init() {}

    func sendWorkoutState(_ state: WorkoutState) { }
    func sendTimerUpdate(timeRemaining: Int) { }
    func sendFeedbackEvent(_ event: FeedbackType) { }
    func sendControlMessage(_ messageType: ControlMessage) { }
}

#endif
