// WorkoutConnectivityTypes.swift
// Shared types used for WatchConnectivity communication between iOS and watchOS
// These types must match exactly on both platforms

import Foundation

// MARK: - Shared Enums

enum FeedbackType: String, Codable {
    case start
    case warning
    case end
    case complete
}

enum ControlMessage: String, Codable {
    case workoutPaused
    case workoutResumed
    case workoutStopped
}

// MARK: - Shared Structs

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

// MARK: - Health Metrics (Watch → iPhone only)

struct WatchHealthMetrics: Codable {
    let heartRate: Double
    let activeCalories: Double
    let isWorkoutActive: Bool
}
