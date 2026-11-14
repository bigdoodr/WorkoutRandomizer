//  PlayerOverlay.swift
//  Bodyweight WorkoutRandomizer
//
//  What's drawn over a workout video, Fitness+ style:
//   • the countdown — always, with or without an Apple Watch — as the largest element;
//   • during a live Watch workout only: heart rate, a coloured zone pill, Burn Type, calories
//     and elapsed time.
//
//  `.corner` sits over the video (countdown top-right, Watch numbers top-left, so the bottom stays
//  free for the system's playback controls). `.panel` is the same content enlarged, standing in
//  for the video on rest screens and when video is turned off.

import SwiftUI

/// The live Watch numbers shown beside the countdown.
struct LiveMetricsSnapshot: Equatable {
    let heartRate: Double
    let zone: WorkoutZoneInfo
    let calories: Double
    /// Whole-workout elapsed time (exercise + rest), in seconds.
    let elapsedSeconds: Int
}

struct PlayerOverlay: View {
    enum Style {
        case corner
        case panel
    }

    let countdown: Int
    /// 0...1 progress through the current step, drawn as a thin bar along the bottom. Optional.
    var progress: Double? = nil
    /// Present only during a live Apple Watch workout.
    var live: LiveMetricsSnapshot? = nil
    var style: Style = .corner

    private var urgent: Bool { countdown > 0 && countdown <= 3 }

    private var elapsedText: String {
        guard let live else { return "" }
        return String(format: "%d:%02d", live.elapsedSeconds / 60, live.elapsedSeconds % 60)
    }

    private func heartRateText(_ live: LiveMetricsSnapshot) -> String {
        live.heartRate > 0 ? "\(Int(live.heartRate))" : "--"
    }

    var body: some View {
        Group {
            switch style {
            case .corner: corner
            case .panel: panel
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var text = "\(countdown) seconds remaining"
        if let live {
            text += ", heart rate \(heartRateText(live)) beats per minute, \(live.zone.name), \(live.zone.burnType), \(Int(live.calories)) kilocalories, \(elapsedText) elapsed"
        }
        return text
    }

    // MARK: Corner (over the video)

    private var corner: some View {
        HStack(alignment: .top, spacing: 8) {
            if let live { cornerMetrics(live) }
            Spacer(minLength: 0)
            Text("\(countdown)")
                .font(.system(size: 58, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(urgent ? Color.red : Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) { progressBar(tint: .white) }
    }

    private func cornerMetrics(_ live: LiveMetricsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text(heartRateText(live))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Text("BPM")
                    .font(.caption2)
                    .opacity(0.8)
            }
            HStack(spacing: 6) {
                Text(live.zone.name)
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(live.zone.color, in: Capsule())
                Text(live.zone.burnType)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(spacing: 10) {
                Label("\(Int(live.calories))", systemImage: "flame.fill")
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
    }

    // MARK: Panel (in the video's place)

    private var panel: some View {
        VStack(spacing: 6) {
            Text("\(countdown)")
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(urgent ? Color.red : Color.primary)
            if let live {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                        .font(.title3)
                    Text(heartRateText(live))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("BPM")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text(live.zone.name)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(live.zone.color, in: Capsule())
                    Text(live.zone.burnType)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                HStack(spacing: 22) {
                    Label("\(Int(live.calories)) kcal", systemImage: "flame.fill")
                        .foregroundStyle(.orange, .primary)
                    Label(elapsedText, systemImage: "timer")
                        .monospacedDigit()
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) { progressBar(tint: .accentColor) }
    }

    @ViewBuilder
    private func progressBar(tint: Color) -> some View {
        if let progress {
            ProgressView(value: min(max(progress, 0), 1))
                .progressViewStyle(.linear)
                .tint(tint)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
        }
    }
}
