// WorkoutSessionManager.swift
// Manages HealthKit workout sessions on watchOS

#if os(watchOS)
import Foundation
import Combine
import HealthKit
import WatchKit
import WatchConnectivity

class WorkoutSessionManager: NSObject, ObservableObject {
    static let shared = WorkoutSessionManager()
    
    let healthStore = HKHealthStore()
    
    @Published var isWorkoutActive = false
    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var peakHeartRate: Double = 0
    @Published var currentZoneIndex: Int? = nil
    
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// Guards against two concurrent start requests (e.g. the watch Start button
    /// and the iPhone's startWatchApp racing each other).
    private var isStartingSession = false
    /// Configuration delivered by the iPhone via startWatchApp → handle(_:).
    /// Held until the user (or an incoming playing state) actually starts the
    /// session, so launching the watch app doesn't record a session prematurely.
    private(set) var preparedConfiguration: HKWorkoutConfiguration?

    func prepare(configuration: HKWorkoutConfiguration) {
        preparedConfiguration = configuration
    }

    func clearPreparedConfiguration() {
        preparedConfiguration = nil
    }
    
    private override init() {
        super.init()
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        let typesToShare: Set<HKSampleType> = [
            HKQuantityType.workoutType()
        ]
        
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .cyclingPower)!,
            HKObjectType.workoutType()
        ]
        
        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            return true
        } catch {
            print("HealthKit authorization failed: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Workout Lifecycle
    
    func startWorkout(configuration: HKWorkoutConfiguration? = nil) async {
        // Avoid creating a second session when one is already running or starting
        // (e.g. the user started from the watch AND the iPhone triggered startWatchApp).
        guard session == nil, !isStartingSession else { return }
        isStartingSession = true
        defer { isStartingSession = false }

        let config = configuration ?? preparedConfiguration ?? defaultConfiguration()
        
        // Request authorization first
        let authorized = await requestAuthorization()
        guard authorized else {
            print("HealthKit not authorized, cannot start workout session")
            return
        }
        
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            builder = session?.associatedWorkoutBuilder()
        } catch {
            print("Failed to create workout session: \(error.localizedDescription)")
            return
        }
        
        guard let session = session, let builder = builder else { return }
        
        session.delegate = self
        builder.delegate = self
        
        let source = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
        builder.dataSource = source
        
        let startDate = Date()
        session.startActivity(with: startDate)

        // Use the user's preferred HR zone config if one exists; otherwise install
        // a standard 5-zone fallback so zone tracking is always active.
        if #available(watchOS 27, *) {
            let hrType = HKQuantityType(.heartRate)
            let existingConfig = try? await builder.zoneConfiguration(for: hrType)
            if existingConfig == nil {
                let bpm = HKUnit.count().unitDivided(by: .minute())
                let boundaries: [HKQuantity] = [
                    HKQuantity(unit: bpm, doubleValue: 114),  // Z1/Z2 ~60% of 190 max
                    HKQuantity(unit: bpm, doubleValue: 133),  // Z2/Z3 ~70%
                    HKQuantity(unit: bpm, doubleValue: 152),  // Z3/Z4 ~80%
                    HKQuantity(unit: bpm, doubleValue: 171),  // Z4/Z5 ~90%
                ]
                let fallback = HKWorkoutZoneConfiguration(quantityType: hrType, zoneBoundaries: boundaries)
                try? await builder.setCustomZoneConfiguration(fallback, for: hrType)
            }
        }

        do {
            try await builder.beginCollection(at: startDate)
        } catch {
            print("Failed to begin workout collection: \(error.localizedDescription)")
            return
        }
        
        await MainActor.run {
            self.isWorkoutActive = true
        }
        
        print("HealthKit workout session started")
    }
    
    func pauseWorkout() {
        session?.pause()
    }
    
    func resumeWorkout() {
        session?.resume()
    }
    
    func endWorkout() {
        guard let session = session else { return }
        session.stopActivity(with: Date())
        session.end()
        // Builder finishWorkout is called in the delegate when state changes to .ended
    }
    
    // MARK: - Helpers
    
    private func defaultConfiguration() -> HKWorkoutConfiguration {
        let config = HKWorkoutConfiguration()
        config.activityType = .highIntensityIntervalTraining
        config.locationType = .indoor
        return config
    }
    
    private func resetWorkout() {
        session = nil
        builder = nil
        preparedConfiguration = nil

        DispatchQueue.main.async {
            self.isWorkoutActive = false
            self.heartRate = 0
            self.activeCalories = 0
            self.peakHeartRate = 0
            self.currentZoneIndex = nil
        }
    }

    // Snapshots current zone durations from the live builder for use in the
    // recap. Must be called before endWorkout() tears the builder down.
    func captureCurrentHRZones() -> [(name: String, seconds: TimeInterval)] {
        guard #available(watchOS 27, *) else { return [] }
        guard let group = builder?.zoneGroup(for: HKQuantityType(.heartRate)) else { return [] }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return group.zoneDurations.map { dur in
            let zoneNum = dur.zone.index + 1
            let minStr = dur.zone.minimum.map { "\(Int($0.doubleValue(for: bpm)))" }
            let maxStr = dur.zone.maximum.map { "\(Int($0.doubleValue(for: bpm)))" }
            let label: String
            switch (minStr, maxStr) {
            case (nil, let max?):    label = "Zone \(zoneNum) (<\(max) bpm)"
            case (let min?, nil):    label = "Zone \(zoneNum) (>\(min) bpm)"
            case (let min?, let max?): label = "Zone \(zoneNum) (\(min)–\(max) bpm)"
            case (nil, nil):         label = "Zone \(zoneNum)"
            }
            return (name: label, seconds: dur.duration)
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutSessionManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        print("Workout session state: \(fromState.rawValue) -> \(toState.rawValue)")
        
        DispatchQueue.main.async {
            self.isWorkoutActive = (toState == .running || toState == .paused)
        }
        
        if toState == .ended {
            Task {
                do {
                    try await builder?.endCollection(at: date)
                    try await builder?.finishWorkout()
                    print("Workout saved to HealthKit")
                } catch {
                    print("Failed to save workout: \(error.localizedDescription)")
                }
                resetWorkout()
            }
        }
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session failed: \(error.localizedDescription)")
        resetWorkout()
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            
            if let statistics = workoutBuilder.statistics(for: quantityType) {
                DispatchQueue.main.async {
                    switch quantityType {
                    case HKQuantityType.quantityType(forIdentifier: .heartRate):
                        let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
                        self.heartRate = statistics.mostRecentQuantity()?.doubleValue(for: heartRateUnit) ?? 0
                        if self.heartRate > self.peakHeartRate {
                            self.peakHeartRate = self.heartRate
                        }
                    case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
                        let energyUnit = HKUnit.kilocalorie()
                        self.activeCalories = statistics.sumQuantity()?.doubleValue(for: energyUnit) ?? 0
                    default:
                        break
                    }
                    
                    // Send updated metrics to iPhone
                    self.sendHealthMetricsToPhone()
                }
            }
        }
    }
    
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle workout events if needed
    }

    // MARK: - Live zone tracking

    @available(watchOS 27, *)
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didUpdateWorkoutZone zoneUpdate: HKLiveWorkoutBuilder.ZoneUpdate) {
        let newIndex = zoneUpdate.newZoneDuration?.zone.index
        DispatchQueue.main.async {
            let previousIndex = self.currentZoneIndex
            self.currentZoneIndex = newIndex
            // Haptic tap on every zone transition so the user feels the change
            if newIndex != previousIndex {
                WKInterfaceDevice.current().play(.notification)
            }
        }
    }
    
    // MARK: - Send Health Metrics to iPhone
    
    private func sendHealthMetricsToPhone() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.isReachable else { return }
        
        // Create metrics payload
        let metrics: [String: Any] = [
            "heartRate": heartRate,
            "activeCalories": activeCalories,
            "isWorkoutActive": isWorkoutActive
        ]
        
        // Encode to data
        do {
            let data = try JSONSerialization.data(withJSONObject: metrics)
            let message: [String: Any] = ["type": "healthMetrics", "payload": data]
            session.sendMessage(message, replyHandler: nil) { error in
                print("Failed to send health metrics to iPhone: \(error.localizedDescription)")
            }
        } catch {
            print("Failed to encode health metrics: \(error.localizedDescription)")
        }
    }
}
#endif
