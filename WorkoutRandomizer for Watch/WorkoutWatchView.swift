// WorkoutWatchView.swift
// Apple Watch view for displaying workout progress
// This file should be added to the Watch App target after creation

#if os(watchOS)
import SwiftUI
import WatchKit

struct WorkoutWatchView: View {
    @StateObject private var connectivityManager = WorkoutConnectivityManager.shared
    @StateObject private var sessionManager = WorkoutSessionManager.shared
    @State private var showEndWorkoutConfirmation = false
    
    var workoutState: WorkoutState? {
        connectivityManager.workoutState
    }
    
    var body: some View {
        Group {
            if let summary = connectivityManager.completedSummary {
                completedRecapView(summary: summary)
            } else {
                activeWorkoutView
            }
        }
        .confirmationDialog(
            "End Workout?",
            isPresented: $showEndWorkoutConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Workout", role: .destructive) {
                sessionManager.endWorkout()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will stop fitness tracking and save your workout to Health.")
        }
        .alert(
            "Start Fitness Tracking?",
            isPresented: $connectivityManager.shouldPromptToStartTracking
        ) {
            Button("Start") {
                Task {
                    await sessionManager.startWorkout()
                }
            }
            Button("Not Now", role: .cancel) { }
        } message: {
            Text("A workout is running on your iPhone. Would you like to track it with Apple Health?")
        }
    }

    @ViewBuilder
    private func completedRecapView(summary: WatchCompletedSummary) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.teal)

                Text("\(summary.label) Complete!")
                    .font(.headline)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: summary.label == "Stretch" ? "figure.cooldown" : "figure.run")
                        Text("\(summary.count) \(summary.label == "Stretch" ? "stretches" : "exercises")")
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                        Text(formattedTime(summary.totalSeconds))
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Button("Done") {
                    connectivityManager.dismissCompleted()
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .padding(.top, 4)
            }
            .padding()
        }
    }

    private func formattedTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    @ViewBuilder
    private var activeWorkoutView: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let state = workoutState {
                    // Current Exercise Name
                    Text(state.currentExerciseName)
                        .font(.title3)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(state.isRest ? .blue : .primary)
                    
                    // Timer Display
                    Text("\(state.timeRemaining)")
                        .font(.system(size: 56, weight: .bold, design: .monospaced))
                        .foregroundStyle(state.timeRemaining <= 3 && state.timeRemaining > 0 ? .red : .green)
                    
                    // Progress Indicator
                    Text("\(state.currentIndex + 1) of \(state.totalExercises)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // HealthKit metrics
                    if sessionManager.isWorkoutActive {
                        HStack(spacing: 12) {
                            if sessionManager.heartRate > 0 {
                                Label("\(Int(sessionManager.heartRate))", systemImage: "heart.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                            if sessionManager.activeCalories > 0 {
                                Label("\(Int(sessionManager.activeCalories))", systemImage: "flame.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    
                    // Next Exercise
                    if let nextName = state.nextExerciseName {
                        VStack(spacing: 2) {
                            Text("Next:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(nextName)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(nextName == "Rest" ? .blue : .primary)
                        }
                    }
                    
                    // Status
                    if state.isPaused {
                        Label("Paused", systemImage: "pause.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if state.isPlaying {
                        Label("Active", systemImage: "play.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    
                    // End Workout button - always visible when a workout is active
                    if sessionManager.isWorkoutActive {
                        Button(role: .destructive) {
                            showEndWorkoutConfirmation = true
                        } label: {
                            Label("End Workout", systemImage: "stop.fill")
                                .font(.caption)
                        }
                        .padding(.top, 8)
                    }
                    
                } else if connectivityManager.isReadyToStart {
                    // iPhone is waiting — show Start button on watch
                    VStack(spacing: 16) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)

                        Text("Ready to Start")
                            .font(.headline)
                            .multilineTextAlignment(.center)

                        Text("Tap Start to begin and track your fitness")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button {
                            connectivityManager.sendRequestStart()
                        } label: {
                            Label("Start Workout", systemImage: "play.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .padding(.top, 4)
                    }
                    .padding()
                } else {
                    // No workout active
                    VStack(spacing: 16) {
                        Image(systemName: "applewatch")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        Text("No Active Workout")
                            .font(.headline)
                            .multilineTextAlignment(.center)

                        Text("Start a workout on your iPhone")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if !connectivityManager.isWatchConnected {
                            Label("Connecting...", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }

                        // Show end button even if connectivity was lost but HealthKit session is still running
                        if sessionManager.isWorkoutActive {
                            Button(role: .destructive) {
                                showEndWorkoutConfirmation = true
                            } label: {
                                Label("End Workout", systemImage: "stop.fill")
                                    .font(.caption)
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding()
                }
            }
            .padding()
        }
    }
}

#Preview {
    WorkoutWatchView()
}
#endif
