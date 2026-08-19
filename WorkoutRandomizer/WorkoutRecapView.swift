//  WorkoutRecapView.swift
//  Bodyweight WorkoutRandomizer
//
//  Post-workout summary screen and its stat cards.
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

// MARK: - WorkoutRecapView

struct WorkoutRecapView: View {
    let completedExercises: [String]
    let totalExerciseTime: Int
    let totalRestTime: Int
    let totalCalories: Double
    let peakHeartRate: Double
    let averageHeartRate: Double
    var hrZoneDurations: [(name: String, seconds: TimeInterval)] = []
    var intention: WorkoutIntention = .generalFitness
    let onDismiss: () -> Void

    private var totalTime: Int { totalExerciseTime + totalRestTime }

    private var targetZoneIndices: [Int] {
        switch intention {
        case .generalFitness:  return [1, 2]
        case .fatBurn:         return [1, 2]
        case .cardioEndurance: return [2, 3]
        case .strengthPower:   return [3, 4]
        }
    }

    private var targetZoneLabel: String {
        switch intention {
        case .generalFitness:  return "Zones 2–3"
        case .fatBurn:         return "Zones 2–3"
        case .cardioEndurance: return "Zones 3–4"
        case .strengthPower:   return "Zones 4–5"
        }
    }

    // Zones 4-5 are meant for short bursts, not the bulk of a session (standard HR
    // zone guidance: Zone 4 is "only short phases possible", Zone 5 is "unsustainable
    // for more than 1-3 minutes"). Crediting unlimited time in those zones toward
    // "Excellent" alignment would reward unsafe sustained exertion, so credited time
    // is capped: Zone 5 caps at 3 continuous-equivalent minutes, Zone 4 caps at 40% of
    // total session time. `isOverexerted` checks the raw (uncapped) time so the UI can
    // still warn about it even though the score no longer rewards it.
    private static let zone5SafeCapSeconds: Double = 180
    private static let zone4SafeCapFraction: Double = 0.4

    private var isOverexerted: Bool {
        guard totalTime > 0 else { return false }
        let zone5Seconds = hrZoneDurations.count > 4 ? hrZoneDurations[4].seconds : 0
        let zone4Seconds = hrZoneDurations.count > 3 ? hrZoneDurations[3].seconds : 0
        return zone5Seconds > Self.zone5SafeCapSeconds
            || zone4Seconds > Double(totalTime) * Self.zone4SafeCapFraction
    }

    private var alignmentFraction: Double {
        let total = hrZoneDurations.reduce(0.0) { $0 + $1.seconds }
        guard total > 0 else { return 0 }
        let targetTime = targetZoneIndices.compactMap { idx -> Double? in
            guard idx < hrZoneDurations.count else { return nil }
            let seconds = hrZoneDurations[idx].seconds
            switch idx {
            case 4:  return min(seconds, Self.zone5SafeCapSeconds)
            case 3:  return min(seconds, total * Self.zone4SafeCapFraction)
            default: return seconds
            }
        }.reduce(0.0, +)
        return targetTime / total
    }

    private var alignmentLabel: String {
        switch alignmentFraction {
        case 0.8...: return "Excellent"
        case 0.6..<0.8: return "Good"
        case 0.4..<0.6: return "Moderate"
        default: return "Low"
        }
    }

    private var alignmentColor: Color {
        switch alignmentFraction {
        case 0.6...: return .green
        case 0.4..<0.6: return .yellow
        default: return .orange
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.green)
                        Text("Workout Complete!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    .padding(.top, 8)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        RecapStatCard(title: "Total Time",     value: formatted(totalTime),         icon: "clock",            color: .blue)
                        RecapStatCard(title: "Exercise Time",  value: formatted(totalExerciseTime),  icon: "figure.run",       color: .green)
                        RecapStatCard(title: "Exercises Done", value: "\(completedExercises.count)", icon: "checkmark.square", color: .orange)
                        RecapStatCard(title: "Rest Time",      value: formatted(totalRestTime),      icon: "pause.circle",     color: .purple)
                        if totalCalories > 0 {
                            RecapStatCard(title: "Calories",   value: "\(Int(totalCalories)) kcal", icon: "flame.fill",   color: .orange)
                        }
                        if peakHeartRate > 0 {
                            RecapStatCard(title: "Peak HR",    value: "\(Int(peakHeartRate)) BPM",  icon: "heart.fill",   color: .red)
                        }
                        if averageHeartRate > 0 {
                            RecapStatCard(title: "Avg HR",     value: "\(Int(averageHeartRate)) BPM", icon: "heart",      color: .pink)
                        }
                        if !hrZoneDurations.isEmpty {
                            RecapStatCard(title: intention.rawValue, value: "\(alignmentLabel)", icon: intention.icon, color: alignmentColor)
                        }
                    }

                    if isOverexerted {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("You spent extended time in Zones 4–5. These zones are meant for short bursts (Zone 5 is unsustainable past 1–3 minutes) — consider more recovery between pushes next time.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }

                    if !hrZoneDurations.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Time in Zone", systemImage: "heart.text.square.fill")
                                .font(.headline)
                            ForEach(Array(hrZoneDurations.enumerated()), id: \.offset) { idx, entry in
                                HStack(spacing: 10) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(zoneColor(idx))
                                        .frame(width: 4, height: 20)
                                    Text(entry.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(formatted(Int(entry.seconds)))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.secondary)
                                    // Proportion bar
                                    let total = hrZoneDurations.reduce(0) { $0 + $1.seconds }
                                    let fraction = total > 0 ? entry.seconds / total : 0
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Color.gray.opacity(0.15))
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(zoneColor(idx).opacity(0.7))
                                                .frame(width: geo.size.width * fraction)
                                        }
                                    }
                                    .frame(width: 60, height: 6)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if !completedExercises.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Exercises Completed")
                                .font(.headline)
                            ForEach(Array(completedExercises.enumerated()), id: \.offset) { i, name in
                                HStack {
                                    Text("\(i + 1).")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, alignment: .leading)
                                    Text(name)
                                        .font(.subheadline)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding()
            }
            .navigationTitle("Recap")
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { onDismiss() }
                        .fontWeight(.semibold)
                }
            }
#else
            .toolbar {
                ToolbarItem {
                    Button("Done") { onDismiss() }
                        .fontWeight(.semibold)
                }
            }
#endif
        }
    }

    private func formatted(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func zoneColor(_ index: Int) -> Color {
        switch index {
        case 0: return .blue
        case 1: return .green
        case 2: return .yellow
        case 3: return .orange
        default: return .red
        }
    }
}

struct RecapStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
