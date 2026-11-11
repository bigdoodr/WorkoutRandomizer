//  WorkoutLiveStatsView.swift
//  Bodyweight WorkoutRandomizer
//
//  Live heart-rate and zone display shown during a workout.
//  Extracted from WorkoutRandomizer.swift — no behaviour change.

import SwiftUI
internal import UniformTypeIdentifiers
import Observation
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(AVKit)
import AVKit
#endif
#if canImport(HealthKit)
import HealthKit
#endif
#if os(macOS)
import AppKit
#endif

// MARK: - WorkoutLiveStatsView

struct WorkoutLiveStatsView: View {
    let exerciseTime: Int
    let heartRate: Double
    let hasWatchData: Bool
    let intention: WorkoutIntention
    var zoneThresholds: [Double] = []
    /// The zone the Apple Watch itself reported, when it has. Takes precedence over anything
    /// worked out here, so the zone and Burn Type match the wrist.
    var watchZoneIndex: Int? = nil

    @State private var showingZonePopover = false
    private var hrZones = HRZoneSettings.shared

    /// Boundaries for the BPM ranges in the popover: the Watch's, else the age-based fallback.
    private var effectiveThresholds: [Double] {
        ZoneResolver.boundaries(liveThresholds: zoneThresholds)
    }

    private var hrInfo: (zone: String, color: Color, nutrient: String) {
        let info = ZoneResolver.resolve(heartRate: heartRate, watchZoneIndex: watchZoneIndex, liveThresholds: zoneThresholds)
        return (info.name, info.color, info.burnType)
    }

    private func zoneBPMRange(index: Int) -> String {
        let t = effectiveThresholds
        let lower = index > 0 && index - 1 < t.count ? Int(t[index - 1]) : nil
        let upper = index < t.count ? Int(t[index]) : nil
        switch (lower, upper) {
        case (nil, let u?): return "< \(u) BPM"
        case (let l?, nil): return "\(l)+ BPM"
        case (let l?, let u?): return "\(l)–\(u) BPM"
        default: return "—"
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 2) {
                Image(systemName: "stopwatch")
                    .foregroundStyle(.blue)
                Text(formattedTime(exerciseTime))
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.semibold)
                Text("Ex. Time")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if hasWatchData {
                Divider().frame(height: 40)

                Button {
                    showingZonePopover = true
                } label: {
                    VStack(spacing: 2) {
                        HStack(spacing: 3) {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundStyle(hrInfo.color)
                            Image(systemName: "info.circle")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(hrInfo.zone)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(hrInfo.color)
                        Text("HR Zone")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingZonePopover) {
                    HRZonePopoverView(zone: hrInfo.zone, color: hrInfo.color, intention: intention, zoneThresholds: zoneThresholds)
                }

                Divider().frame(height: 40)
                VStack(spacing: 2) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(hrInfo.color)
                    Text(hrInfo.nutrient)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("Burn Type")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formattedTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct HRZonePopoverView: View {
    let zone: String
    let color: Color
    let intention: WorkoutIntention
    var zoneThresholds: [Double] = []
    private var hrZones = HRZoneSettings.shared

    private func zoneBPMRange(index: Int) -> String {
        let t = zoneThresholds.isEmpty ? hrZones.zoneBoundaries : zoneThresholds
        let lower = index > 0 && index - 1 < t.count ? Int(t[index - 1]) : nil
        let upper = index < t.count ? Int(t[index]) : nil
        switch (lower, upper) {
        case (nil, let u?): return "< \(u) BPM"
        case (let l?, nil): return "\(l)+ BPM"
        case (let l?, let u?): return "\(l)–\(u) BPM"
        default: return "—"
        }
    }

    private var details: [String: (bpmRange: String, description: String)] {
        return [
            "Zone 1": (bpmRange: zoneBPMRange(index: 0), description: "Very light. Active recovery."),
            "Zone 2": (bpmRange: zoneBPMRange(index: 1), description: "Light aerobic. Optimal fat oxidation."),
            "Zone 3": (bpmRange: zoneBPMRange(index: 2), description: "Moderate aerobic. Mixed carb/fat fuel."),
            "Zone 4": (bpmRange: zoneBPMRange(index: 3), description: "High intensity. Lactate threshold zone."),
            "Zone 5": (bpmRange: zoneBPMRange(index: 4), description: "Maximum effort. Anaerobic capacity."),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(zone)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                Spacer()
                if let d = details[zone] {
                    Text(d.bpmRange)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let d = details[zone] {
                Text(d.description)
                    .font(.subheadline)
            }
            Divider()
            HStack(spacing: 6) {
                Image(systemName: intention.icon)
                    .foregroundStyle(color)
                Text(intention.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            Text(intention.tip(for: zone))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 240, maxWidth: 300)
    }
}
