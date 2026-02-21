// WorkoutConnectivityManager.swift
// Manages WatchConnectivity communication between iOS and watchOS apps

import Foundation
import Combine
import WatchConnectivity
#if os(watchOS)
import WatchKit
#endif

/// Message types for Watch Connectivity
enum WorkoutMessage: String {
    case workoutStarted
    case workoutPaused
    case workoutResumed
    case workoutStopped
    case exerciseChanged
    case timerUpdate
    case feedbackEvent
}

/// Workout state data structure for sharing
struct WorkoutState: Codable {
    let currentExerciseName: String
    let currentIndex: Int
    let totalExercises: Int
    let timeRemaining: Int
    let isRest: Bool
    let nextExerciseName: String?
    let isPlaying: Bool
    let isPaused: Bool
}

/// Feedback event types
enum FeedbackType: String, Codable {
    case start
    case warning
    case end
    case complete
}

class WorkoutConnectivityManager: NSObject, ObservableObject {
    static let shared = WorkoutConnectivityManager()
    
    @Published var workoutState: WorkoutState?
    @Published var isWatchConnected = false
    
    private var session: WCSession?
    
    private override init() {
        super.init()
        
        #if os(iOS)
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
        #elseif os(watchOS)
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
        #endif
    }
    
    private func logWCSessionState(prefix: String, session: WCSession) {
        #if os(iOS)
        print("\(prefix) - activation: \(session.activationState.rawValue), paired: \(session.isPaired), installed: \(session.isWatchAppInstalled), reachable: \(session.isReachable)")
        #else
        print("\(prefix) - activation: \(session.activationState.rawValue)")
        #endif
    }
    
    // MARK: - Send Methods
    
    /// Send workout state update
    func sendWorkoutState(_ state: WorkoutState) {
        guard let session = session else { return }
        logWCSessionState(prefix: "sendWorkoutState", session: session)
        guard session.activationState == .activated else {
            return
        }
        
        #if os(iOS)
        guard session.isPaired && session.isWatchAppInstalled else {
            return
        }
        #endif
        
        do {
            let data = try JSONEncoder().encode(state)
            let message: [String: Any] = [
                "type": WorkoutMessage.exerciseChanged.rawValue,
                "state": data
            ]
            
            // Use updateApplicationContext for state updates
            try session.updateApplicationContext(message)
            
        } catch {
            print("Failed to send workout state: \(error.localizedDescription)")
        }
    }
    
    /// Send immediate timer update
    func sendTimerUpdate(timeRemaining: Int) {
        guard let session = session else { return }
        logWCSessionState(prefix: "sendTimerUpdate", session: session)
        guard session.activationState == .activated else {
            return
        }
        
        #if os(iOS)
        guard session.isReachable else {
            return
        }
        #endif
        
        let message: [String: Any] = [
            "type": WorkoutMessage.timerUpdate.rawValue,
            "time": timeRemaining
        ]
        
        // Use sendMessage for real-time updates
        session.sendMessage(message, replyHandler: nil) { error in
            print("Failed to send timer update: \(error.localizedDescription)")
        }
    }
    
    /// Send feedback event
    func sendFeedbackEvent(_ event: FeedbackType) {
        guard let session = session else { return }
        logWCSessionState(prefix: "sendFeedbackEvent", session: session)
        guard session.activationState == .activated else {
            return
        }
        
        #if os(iOS)
        guard session.isReachable else {
            return
        }
        #endif
        
        let message: [String: Any] = [
            "type": WorkoutMessage.feedbackEvent.rawValue,
            "event": event.rawValue
        ]
        
        session.sendMessage(message, replyHandler: nil) { error in
            print("Failed to send feedback event: \(error.localizedDescription)")
        }
    }
    
    /// Send workout control message
    func sendControlMessage(_ messageType: WorkoutMessage) {
        guard let session = session else { return }
        logWCSessionState(prefix: "sendControlMessage", session: session)
        guard session.activationState == .activated else {
            return
        }
        
        #if os(iOS)
        guard session.isReachable else {
            return
        }
        #endif
        
        let message: [String: Any] = [
            "type": messageType.rawValue
        ]
        
        session.sendMessage(message, replyHandler: nil) { error in
            print("Failed to send control message: \(error.localizedDescription)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WorkoutConnectivityManager: WCSessionDelegate {
    #if os(iOS)
    @available(iOS, introduced: 9.3, deprecated: 13.0)
    func sessionDidDeactivate(_ session: WCSession) {
        // On iOS, after deactivation (e.g., switching watches), reactivate the session
        print("WCSession deactivated on iOS")
        session.activate()
    }
    #endif
    
    
    #if os(iOS)
    @available(iOS, introduced: 9.3, deprecated: 13.0)
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession became inactive")
    }
    #endif
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isWatchConnected = (activationState == .activated)
            
            #if os(iOS)
            print("WC activationDidComplete - state: \(activationState.rawValue), paired: \(session.isPaired), installed: \(session.isWatchAppInstalled), reachable: \(session.isReachable)")
            #else
            print("WC activationDidComplete on watchOS - state: \(activationState.rawValue)")
            #endif
            
            if let error = error {
                print("WCSession activation failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Receive Messages
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        guard let typeString = message["type"] as? String,
              let messageType = WorkoutMessage(rawValue: typeString) else {
            return
        }
        
        DispatchQueue.main.async {
            switch messageType {
            case .timerUpdate:
                // Update watch countdown in real-time when running on watchOS
                #if os(watchOS)
                if let time = message["time"] as? Int {
                    if let state = self.workoutState {
                        let updated = WorkoutState(
                            currentExerciseName: state.currentExerciseName,
                            currentIndex: state.currentIndex,
                            totalExercises: state.totalExercises,
                            timeRemaining: time,
                            isRest: state.isRest,
                            nextExerciseName: state.nextExerciseName,
                            isPlaying: state.isPlaying,
                            isPaused: state.isPaused
                        )
                        self.workoutState = updated
                    } else {
                        // Create a minimal state so the timer is visible even before a full state arrives
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
                #endif
            case .feedbackEvent:
                // Trigger feedback on receiving device
                #if os(watchOS)
                if let eventString = message["event"] as? String,
                   let event = FeedbackType(rawValue: eventString) {
                    self.triggerWatchFeedback(event)
                }
                #endif
            default:
                break
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        guard let typeString = applicationContext["type"] as? String,
              let messageType = WorkoutMessage(rawValue: typeString) else {
            return
        }
        
        DispatchQueue.main.async {
            switch messageType {
            case .exerciseChanged:
                if let stateData = applicationContext["state"] as? Data {
                    do {
                        let state = try JSONDecoder().decode(WorkoutState.self, from: stateData)
                        self.workoutState = state
                    } catch {
                        print("Failed to decode workout state: \(error.localizedDescription)")
                    }
                }
            default:
                break
            }
        }
    }
    
    // MARK: - Watch Feedback
    
    #if os(watchOS)
    private func triggerWatchFeedback(_ event: FeedbackType) {
        let device = WKInterfaceDevice.current()
        
        switch event {
        case .start:
            device.play(.start)
        case .warning:
            device.play(.notification)
        case .end:
            device.play(.stop)
        case .complete:
            device.play(.success)
        }
    }
    #endif
}
