//
//  WorkoutRandomizer_Watch_AppApp.swift
//  WorkoutRandomizer Watch App Watch App
//
//  Created by Casey Scruggs on 2/14/26.
//

import SwiftUI
import WatchKit
import HealthKit
import UserNotifications
import WatchConnectivity

class AppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {

    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

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

    // Show the banner even if the app is already in the foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // When the user taps the notification to open the app, ensure the ready state is set
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.content.userInfo["action"] as? String == "prepareToStart" {
            Task { @MainActor in
                WorkoutConnectivityManager.shared.isReadyToStart = true
            }
        }
        completionHandler()
    }
}

@main
struct WorkoutRandomizer_Watch_App_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            WorkoutWatchView()
        }
        // Keeps the app alive while WCSession delivers pending transfers via its delegate.
        // Without this, the system may suspend the app before the notification can be posted.
        .backgroundTask(.watchConnectivity) {
            while WCSession.default.hasContentPending {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }
}
