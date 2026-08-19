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
    let maxHeartRate: Double
    var zoneThresholds: [Double] = []

    @State private var showingZonePopover = false

    private var hrInfo: (zone: String, color: Color, nutrient: String) {
        let idx: Int
        if !zoneThresholds.isEmpty {
            idx = zoneThresholds.firstIndex(where: { heartRate < $0 }) ?? zoneThresholds.count
        } else {
            let pct = heartRate / maxHeartRate
            switch pct {
            case ..<0.60:     idx = 0
            case 0.60..<0.70: idx = 1
            case 0.70..<0.80: idx = 2
            case 0.80..<0.90: idx = 3
            default:          idx = 4
            }
        }
        switch idx {
        case 0: return ("Zone 1", .green, "Active Recovery")
        case 1: return ("Zone 2", .yellow, "Fat Burn")
        case 2: return ("Zone 3", .orange, "Mixed")
        case 3: return ("Zone 4", .red, "Carb Burn")
        default: return ("Zone 5", .purple, "Peak Effort")
        }
    }

    private func zoneBPMRange(index: Int) -> String {
        let t = zoneThresholds.isEmpty
            ? [maxHeartRate * 0.60, maxHeartRate * 0.70, maxHeartRate * 0.80, maxHeartRate * 0.90]
            : zoneThresholds
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
                    HRZonePopoverView(zone: hrInfo.zone, color: hrInfo.color, intention: intention, maxHeartRate: maxHeartRate, zoneThresholds: zoneThresholds)
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
    let maxHeartRate: Double
    var zoneThresholds: [Double] = []

    private func zoneBPMRange(index: Int) -> String {
        let t = zoneThresholds.isEmpty
            ? [maxHeartRate * 0.60, maxHeartRate * 0.70, maxHeartRate * 0.80, maxHeartRate * 0.90]
            : zoneThresholds
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
