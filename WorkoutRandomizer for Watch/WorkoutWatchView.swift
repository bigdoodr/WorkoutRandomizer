// WorkoutWatchView.swift
// Apple Watch view for displaying workout progress
// This file should be added to the Watch App target after creation

#if os(watchOS)
import SwiftUI
import WatchKit

struct WorkoutWatchView: View {
    @StateObject private var connectivityManager = WorkoutConnectivityManager.shared
    
    var workoutState: WorkoutState? {
        connectivityManager.workoutState
    }
    
    var body: some View {
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
                }
                .padding()
            }
        }
        .padding()
    }
}

#Preview {
    WorkoutWatchView()
}
#endif
