// WorkoutConnectivityManager+iOS.swift
// Sends workout state to watchOS and receives HealthKit metrics

#if os(iOS)
import Foundation
import Combine
import WatchConnectivity

// MARK: - iOS-specific WorkoutConnectivityManager

@MainActor
class WorkoutConnectivityManager: ObservableObject {
    static let shared = WorkoutConnectivityManager()
    
    @Published var isWatchConnected = false
    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var isWatchWorkoutActive = false
    
    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    
    private init() {
        if let session = session {
            session.delegate = WatchConnectivityDelegate.shared
            session.activate()
        }
    }
    
    // MARK: - Send workout state to Watch
    
    func sendWorkoutState(_ state: WorkoutState) {
        guard let session = session, session.isReachable else {
            // If not reachable, use application context for delivery when watch wakes up
            sendWorkoutStateViaContext(state)
            return
        }
        
        do {
            let data = try JSONEncoder().encode(state)
            let message: [String: Any] = ["type": "workoutState", "payload": data]
            session.sendMessage(message, replyHandler: nil) { error in
                print("Failed to send workout state: \(error.localizedDescription)")
                // Fall back to application context
                self.sendWorkoutStateViaContext(state)
            }
        } catch {
            print("Failed to encode workout state: \(error.localizedDescription)")
        }
    }
    
    private func sendWorkoutStateViaContext(_ state: WorkoutState) {
        guard let session = session else { return }
        do {
            let data = try JSONEncoder().encode(state)
            let context: [String: Any] = ["workoutStatePayload": data]
            try session.updateApplicationContext(context)
        } catch {
            print("Failed to send workout state via context: \(error.localizedDescription)")
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
        
        // Clear application context when workout is stopped
        if control == .workoutStopped {
            do {
                try session.updateApplicationContext([:])
            } catch {
                print("Failed to clear application context: \(error.localizedDescription)")
            }
        }
        
        guard session.isReachable else { return }
        let message: [String: Any] = ["type": "control", "message": control.rawValue]
        session.sendMessage(message, replyHandler: nil)
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
        }
        if let error {
            print("WCSession activation failed: \(error.localizedDescription)")
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
        // Reactivate the session for the new Apple Watch
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
        default:
            break
        }
    }
}

#endif
