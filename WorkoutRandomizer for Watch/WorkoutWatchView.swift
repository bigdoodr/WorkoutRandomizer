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
                WorkoutConnectivityManager.shared.sendRequestStop()
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

                    if summary.peakHeartRate > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                            Text("\(Int(summary.peakHeartRate)) BPM peak")
                                .fontWeight(.medium)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if summary.activeCalories > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.orange)
                            Text("\(Int(summary.activeCalories)) kcal")
                                .fontWeight(.medium)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
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
                    if state.isRest {
                        // Rest / Get Ready phase: emphasize what's coming next
                        Text(state.currentExerciseName)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)

                        Text("\(state.timeRemaining)")
                            .font(.system(size: 56, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)

                        if let nextName = state.nextExerciseName {
                            VStack(spacing: 2) {
                                Text("Next up")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(nextName)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    } else {
                        // Active exercise/stretch
                        Text(state.currentExerciseName)
                            .font(.title3)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)

                        if let side = state.sideLabel {
                            Text(side)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.indigo)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.indigo.opacity(0.2))
                                .clipShape(Capsule())
                        }

                        Text("\(state.timeRemaining)")
                            .font(.system(size: 56, weight: .bold, design: .monospaced))
                            .foregroundStyle(state.timeRemaining <= 3 && state.timeRemaining > 0 ? .red : .green)
                    }

                    // Progress Indicator
                    if state.totalExercises > 0 {
                        Text("\(state.currentIndex + 1) of \(state.totalExercises)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

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

                    // Next Exercise (during active phase; rest phase shows it above)
                    if !state.isRest, let nextName = state.nextExerciseName {
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

                } else if connectivityManager.isAwaitingSessionStart {
                    // User tapped Start on the watch; waiting for the iPhone to begin
                    StartingView {
                        connectivityManager.sendRequestStart()
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

                        Text("Starts the session on both devices and tracks your fitness")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button {
                            // Start fitness tracking right away, then tell the
                            // iPhone to begin the routine — one tap does it all.
                            Task {
                                await sessionManager.startWorkout()
                            }
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

/// Shown after the user taps Start on the watch, while waiting for the iPhone
/// to begin the routine. If the phone hasn't started after a few seconds, a
/// fallback button appears to re-send the start request.
private struct StartingView: View {
    let onRetry: () -> Void
    @State private var showRetry = false

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
                .padding(.top, 8)

            Text("Starting…")
                .font(.headline)

            Text("Get in position — your session is about to begin")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if showRetry {
                Button {
                    onRetry()
                } label: {
                    Label("Start Now", systemImage: "play.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .padding()
        .task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            withAnimation { showRetry = true }
        }
    }
}

#Preview {
    WorkoutWatchView()
}
#endif
