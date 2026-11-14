// WatchHealthMetrics.swift
// The live numbers the Apple Watch sends to the iPhone during a workout. Shared so the Watch
// encodes, and the iPhone decodes, exactly the same thing — whichever route carries it
// (a mirrored HealthKit workout session, or a WatchConnectivity message as the fallback).

import Foundation

nonisolated struct WatchHealthMetrics: Codable, Sendable {
    let heartRate: Double
    let activeCalories: Double
    /// Whether the Watch's workout session is running (or paused) right now.
    let isWorkoutActive: Bool
    /// The zone HealthKit says the wearer is in (zero-based); absent or negative when unknown.
    var zoneIndex: Int? = nil
    /// The Watch's zone boundaries, repeated with every sample so the iPhone never depends on the
    /// single message sent at session start having arrived.
    var zoneThresholds: [Double]? = nil
}
