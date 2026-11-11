//  WatchMetricsOverlay.swift
//  Bodyweight WorkoutRandomizer
//
//  Live Apple Watch numbers drawn over the exercise video, Fitness+ style: heart rate, a coloured
//  zone pill, calories and elapsed time. On rest screens there is no video, so the same numbers
//  fill the video's place as a larger panel.
//
//  Only shown while a Watch workout is live (see `WorkoutConnectivityManager.hasLiveWatchSession`).

#if os(iOS)
import SwiftUI

struct WatchMetricsOverlay: View {
    enum Style {
        /// Small, in a corner of the video.
        case corner
        /// Large, standing in for the video on a rest screen.
        case panel
    }

    let heartRate: Double
    let zone: WorkoutZoneInfo
    let calories: Double
    /// Whole-workout elapsed time (exercise + rest), in seconds.
    let elapsedSeconds: Int
    var style: Style = .corner

    private var heartRateText: String { heartRate > 0 ? "\(Int(heartRate))" : "--" }

    private var elapsedText: String {
        String(format: "%d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    private var zonePill: some View {
        Text(zone.name)
            .font(style == .panel ? .subheadline : .caption)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(.horizontal, style == .panel ? 12 : 8)
            .padding(.vertical, style == .panel ? 4 : 2)
            .background(zone.color, in: Capsule())
    }

    var body: some View {
        switch style {
        case .corner: corner
        case .panel: panel
        }
    }

    private var corner: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text(heartRateText)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Text("BPM")
                    .font(.caption2)
                    .opacity(0.8)
            }
            zonePill
            HStack(spacing: 10) {
                Label("\(Int(calories))", systemImage: "flame.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.orange, .white)
                Label(elapsedText, systemImage: "timer")
                    .monospacedDigit()
            }
            .font(.caption)
            .fontWeight(.semibold)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Heart rate \(heartRateText) beats per minute, \(zone.name), \(Int(calories)) kilocalories, \(elapsedText) elapsed")
    }

    private var panel: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .font(.title2)
                Text(heartRateText)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("BPM")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            zonePill
            HStack(spacing: 24) {
                Label("\(Int(calories)) kcal", systemImage: "flame.fill")
                    .foregroundStyle(.orange, .primary)
                Label(elapsedText, systemImage: "timer")
                    .monospacedDigit()
            }
            .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Heart rate \(heartRateText) beats per minute, \(zone.name), \(Int(calories)) kilocalories, \(elapsedText) elapsed")
    }
}
#endif
