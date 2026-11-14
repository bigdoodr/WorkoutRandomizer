//  WatchWorkoutMirror.swift
//  Bodyweight WorkoutRandomizer
//
//  Receives the Apple Watch's workout session on the iPhone through HealthKit workout mirroring.
//
//  Why: live metrics used to travel only as WatchConnectivity messages, which need the Watch app
//  to be reachable — and with the Watch's screen off it often isn't, even though its workout
//  session carries on. A mirrored session rides HealthKit's own link instead, so:
//   • the session's state (running / paused / ended) tells the iPhone whether a Watch workout is
//     live, regardless of reachability — that's what the overlay follows;
//   • the Watch sends each heart-rate / calorie / zone sample to the mirrored session, so the
//     numbers keep arriving with the screen off.
//
//  WatchConnectivity is still used as a fallback (and for the plan, anchors and controls).

#if os(iOS)
import Foundation
import HealthKit
import os

final class WatchWorkoutMirror: NSObject, HKWorkoutSessionDelegate, @unchecked Sendable {
    static let shared = WatchWorkoutMirror()

    private let store = HKHealthStore()
    private let log = Logger(subsystem: "rocks.scruggsfam.productions.WorkoutRandomizer", category: "Mirror")
    private let lock = NSLock()
    private var session: HKWorkoutSession?

    /// Call as soon as the app launches. HealthKit launches the app in the background to deliver a
    /// mirrored session, and the handler has to be in place by then.
    func install() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        store.workoutSessionMirroringStartHandler = { [weak self] mirrored in
            self?.adopt(mirrored)
        }
    }

    /// HealthKit may hand over several sessions during one workout (each reconnect after a dropped
    /// link is a new instance), so the latest replaces the last.
    private func adopt(_ mirrored: HKWorkoutSession) {
        lock.lock()
        session?.delegate = nil
        session = mirrored
        lock.unlock()
        mirrored.delegate = self
        log.notice("Mirrored session started (state \(mirrored.state.rawValue))")
        publish(state: mirrored.state)
    }

    private func publish(state: HKWorkoutSessionState) {
        let active = state == .running || state == .paused
        Task { @MainActor in
            WorkoutConnectivityManager.shared.mirroredSessionStateChanged(active: active)
        }
    }

    // MARK: HKWorkoutSessionDelegate

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        log.notice("Mirrored session \(fromState.rawValue) -> \(toState.rawValue)")
        publish(state: toState)
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        log.error("Mirrored session failed: \(error.localizedDescription)")
    }

    /// The Watch's samples: heart rate, calories, zone and thresholds, as `WatchHealthMetrics`.
    func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        for item in data {
            guard let metrics = try? JSONDecoder().decode(WatchHealthMetrics.self, from: item) else { continue }
            WorkoutConnectivityManager.shared.receiveHealthMetrics(metrics)
        }
    }

    /// The link to the Watch dropped. The session isn't over — the Watch reconnects on its own and
    /// a new mirrored session arrives — so this deliberately does not mark the workout inactive.
    func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        log.notice("Mirrored session disconnected: \(error?.localizedDescription ?? "no error")")
    }
}
#endif
