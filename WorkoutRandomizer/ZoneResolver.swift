//  ZoneResolver.swift
//  Bodyweight WorkoutRandomizer
//
//  One answer to "which heart-rate zone is this?" for everything on the iPhone that shows or
//  reacts to a zone (the live stats panel, the video overlay, the intention banners).
//
//  Order of authority:
//   1. The zone the Apple Watch itself reports (HealthKit's live zone update) — exactly what the
//      Watch shows, whatever its configuration.
//   2. The Watch's zone boundaries (live from this session, else the last ones it reported),
//      applied to the heart rate we have.
//   3. Only when there's no Watch information at all: the age-based boundaries from Settings.
//  Burn Type comes from the zone, so it can't disagree with the zone shown beside it.

import SwiftUI

struct WorkoutZoneInfo: Equatable {
    /// Zero-based zone index (0 = Zone 1).
    let index: Int
    let color: Color
    let burnType: String

    var name: String { "Zone \(index + 1)" }
}

enum ZoneResolver {
    static func info(forIndex index: Int) -> WorkoutZoneInfo {
        switch min(max(index, 0), 4) {
        case 0: return WorkoutZoneInfo(index: 0, color: .green, burnType: "Active Recovery")
        case 1: return WorkoutZoneInfo(index: 1, color: .yellow, burnType: "Fat Burn")
        case 2: return WorkoutZoneInfo(index: 2, color: .orange, burnType: "Mixed")
        case 3: return WorkoutZoneInfo(index: 3, color: .red, burnType: "Carb Burn")
        default: return WorkoutZoneInfo(index: 4, color: .purple, burnType: "Peak Effort")
        }
    }

    /// The boundaries to classify a heart rate against when the Watch hasn't named the zone:
    /// this session's Watch thresholds, else the last the Watch reported, else age-based.
    @MainActor
    static func boundaries(liveThresholds: [Double]) -> [Double] {
        if !liveThresholds.isEmpty { return liveThresholds }
        let settings = HRZoneSettings.shared
        return settings.watchZoneThresholds ?? settings.zoneBoundaries
    }

    @MainActor
    static func resolve(heartRate: Double, watchZoneIndex: Int?, liveThresholds: [Double]) -> WorkoutZoneInfo {
        if let watchZoneIndex { return info(forIndex: watchZoneIndex) }
        let t = boundaries(liveThresholds: liveThresholds)
        return info(forIndex: t.firstIndex(where: { heartRate < $0 }) ?? t.count)
    }
}
