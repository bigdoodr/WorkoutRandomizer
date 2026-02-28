// WorkoutSessionManager.swift
// Manages HealthKit workout sessions on watchOS

#if os(watchOS)
import Foundation
import HealthKit
import WatchKit

class WorkoutSessionManager: NSObject, ObservableObject {
    static let shared = WorkoutSessionManager()
    
    let healthStore = HKHealthStore()
    
    @Published var isWorkoutActive = false
    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0
    
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    
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
        let config = configuration ?? defaultConfiguration()
        
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
        
        DispatchQueue.main.async {
            self.isWorkoutActive = false
            self.heartRate = 0
            self.activeCalories = 0
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
                    case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
                        let energyUnit = HKUnit.kilocalorie()
                        self.activeCalories = statistics.sumQuantity()?.doubleValue(for: energyUnit) ?? 0
                    default:
                        break
                    }
                }
            }
        }
    }
    
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle workout events if needed
    }
}
#endif
