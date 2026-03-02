//
//  WorkoutRandomizer_Watch_AppApp.swift
//  WorkoutRandomizer Watch App Watch App
//
//  Created by Casey Scruggs on 2/14/26.
//

import SwiftUI
import WatchKit
import HealthKit

class AppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        // Called by the system when the iPhone triggers HKHealthStore.startWatchApp(with:)
        Task {
            await WorkoutSessionManager.shared.startWorkout(configuration: workoutConfiguration)
        }
    }
    
    func handleActiveWorkoutRecovery() {
        // Recover from a crash during an active workout session
        WorkoutSessionManager.shared.healthStore.recoverActiveWorkoutSession { session, error in
            if let error = error {
                print("Failed to recover workout session: \(error.localizedDescription)")
                return
            }
            print("Recovered active workout session")
        }
    }
}

@main
struct WorkoutRandomizer_Watch_App_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor var appDelegate: AppDelegate
    
    var body: some Scene {
        WindowGroup {
            WorkoutWatchView()
        }
    }
}
