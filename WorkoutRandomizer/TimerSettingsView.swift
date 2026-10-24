//  TimerSettingsView.swift
//  Bodyweight WorkoutRandomizer
//
//  The Timer tab: timer style, durations, rest, warm-up/cool-down, and the Repeating Blocks and
//  Pyramid options. These used to sit in the middle of the Generate screen; they now live here and
//  write to the shared GeneratorSettings, which the Generate tab reads when it builds a routine.
//
//  The sections are moved over unchanged. The computed properties below forward to the shared
//  settings under the same names those sections already used, so the moved code reads as before.

import SwiftUI

struct TimerSettingsView: View {
    /// Switches to the Generate tab. Supplied by the tab container; the bottom button calls it.
    var onOpenGenerate: (() -> Void)? = nil

    @Bindable private var settings = GeneratorSettings.shared

    private var totalDuration: Int { get { settings.totalDuration } nonmutating set { settings.totalDuration = newValue } }
    private var exerciseDuration: Int { get { settings.exerciseDuration } nonmutating set { settings.exerciseDuration = newValue } }
    private var restDuration: Int { get { settings.restDuration } nonmutating set { settings.restDuration = newValue } }
    private var restLinkedToWork: Bool { get { settings.restLinkedToWork } nonmutating set { settings.restLinkedToWork = newValue } }
    private var restEvery: Int { get { settings.restEvery } nonmutating set { settings.restEvery = newValue } }
    private var shuffleExerciseTime: Bool { get { settings.shuffleExerciseTime } nonmutating set { settings.shuffleExerciseTime = newValue } }
    private var timerStyle: TimerStyle { get { settings.timerStyle } nonmutating set { settings.timerStyle = newValue } }
    private var blocksCount: Int { get { settings.blocksCount } nonmutating set { settings.blocksCount = newValue } }
    private var exercisesPerBlock: Int { get { settings.exercisesPerBlock } nonmutating set { settings.exercisesPerBlock = newValue } }
    private var blockDurations: [Int] { get { settings.blockDurations } nonmutating set { settings.blockDurations = newValue } }
    private var blocksTotalSets: Int { get { settings.blocksTotalSets } nonmutating set { settings.blocksTotalSets = newValue } }
    private var blocksCycleRestLinked: Bool { get { settings.blocksCycleRestLinked } nonmutating set { settings.blocksCycleRestLinked = newValue } }
    private var blocksCycleRestDuration: Int { get { settings.blocksCycleRestDuration } nonmutating set { settings.blocksCycleRestDuration = newValue } }

    private var effectiveRestDuration: Int { settings.effectiveRestDuration }
    private var effectiveBlocksCycleRest: Int { settings.effectiveBlocksCycleRest }
    private var blocksSuperSetSeconds: Int { settings.blocksSuperSetSeconds }
    private var blocksTotalSeconds: Int { settings.blocksTotalSeconds }
    private var blocksAvailableTotalSets: [Int] { settings.blocksAvailableTotalSets }
    private var warmUpSummary: String { settings.warmUpSummary }
    private var coolDownSummary: String { settings.coolDownSummary }
    private var pyramidPlan: WorkoutTiming.PyramidPlan { settings.pyramidPlan }
    private func blocksTotalSeconds(forSets sets: Int) -> Int { settings.blocksTotalSeconds(forSets: sets) }
    private func clampBlocksTotalSets() { settings.clampBlocksTotalSets() }
    private func formatBlockTime(_ seconds: Int) -> String { settings.formatBlockTime(seconds) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                        // Timer Style — Standard always visible; Pyramid + Blocks advanced only
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Timer Style")
                                .font(.title2)
                                .fontWeight(.semibold)

                            // Capsule chips in a scroller rather than a fixed HStack — five
                            // styles will not fit across an iPhone at any sensible font size.
                            OverflowScrollRow(items: TimerStyle.allCases) { style in
                                Button { timerStyle = style } label: {
                                    Text(style.rawValue)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(timerStyle == style ? Color.blue : Color.gray.opacity(0.12))
                                        .foregroundStyle(timerStyle == style ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }

                            if timerStyle.isLadder {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(timerStyle == .addOn
                                         ? "Each round repeats the last one and adds an exercise — round 1 is one exercise, round 2 is that exercise plus a new one, and so on."
                                         : "Rounds build up one exercise at a time, then peel back off until the final round is just the first exercise again.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("Ladder length is chosen to land closest to your selected total duration.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            if timerStyle == .pyramid {
                                pyramidExplainer

                                Toggle(isOn: $settings.shufflePyramidOrder) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Shuffle order")
                                            .font(.subheadline)
                                        Text("Without this, an exercise keeps the same duration on both sides of the climb")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        // Durations — preset chips
                        // Everything except Blocks picks its total duration here; Blocks derives
                        // its own from the cycle picker.
                        if timerStyle != .blocks {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Durations")
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                VStack(alignment: .leading, spacing: 14) {
                                    // Total Duration presets
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Total Duration")
                                            .font(.subheadline)
                                        OverflowScrollRow(items: [5, 10, 20, 30, 45, 60, 90]) { preset in
                                            Button { totalDuration = preset } label: {
                                                Text("\(preset) min")
                                                    .font(.subheadline)
                                                    .padding(.horizontal, 14)
                                                    .padding(.vertical, 8)
                                                    .background(totalDuration == preset ? Color.blue : Color.gray.opacity(0.12))
                                                    .foregroundStyle(totalDuration == preset ? .white : .primary)
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }

                                    if timerStyle != .pyramid {
                                        // Exercise Duration presets, with Shuffle Exercise Time
                                        // (Standard only) sharing the same row — it picks a
                                        // random value from these same presets per exercise
                                        // instead of one fixed length for every exercise. The
                                        // same result can already be built by hand with Custom
                                        // Timers; this just automates it.
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Exercise Duration")
                                                .font(.subheadline)
                                            HStack(spacing: 8) {
                                                ForEach([20, 30, 45, 60], id: \.self) { preset in
                                                    Button { exerciseDuration = preset } label: {
                                                        Text("\(preset)s")
                                                            .font(.subheadline)
                                                            .padding(.horizontal, 16)
                                                            .padding(.vertical, 8)
                                                            .background(exerciseDuration == preset ? Color.blue : Color.gray.opacity(0.12))
                                                            .foregroundStyle(exerciseDuration == preset ? .white : .primary)
                                                            .clipShape(Capsule())
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                                Spacer(minLength: 0)
                                            }
                                            // Shuffle replaces the fixed length entirely, so the
                                            // presets are inert while it's on.
                                            .disabled(timerStyle == .standard && shuffleExerciseTime)
                                            .opacity(timerStyle == .standard && shuffleExerciseTime ? 0.4 : 1)

                                            if timerStyle == .standard {
                                                Toggle(isOn: $settings.shuffleExerciseTime) {
                                                    Text("Shuffle Exercise Time")
                                                        .font(.subheadline)
                                                }
                                                .toggleStyle(.switch)
                                                Text("Each exercise gets its own random duration instead of one fixed length")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }

                                        // Rest Duration — either derived from Exercise Duration
                                        // or picked by hand, toggled by the link button.
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text("Rest Duration")
                                                    .font(.subheadline)
                                                Spacer()
                                                Button {
                                                    // Leaving linked mode seeds the manual value
                                                    // with what was showing, so nothing jumps.
                                                    if restLinkedToWork { restDuration = effectiveRestDuration }
                                                    withAnimation(.easeInOut(duration: 0.15)) {
                                                        restLinkedToWork.toggle()
                                                    }
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: restLinkedToWork ? "link" : "link.badge.plus")
                                                        Text(restLinkedToWork ? "Linked" : "Manual")
                                                    }
                                                    .font(.caption)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 5)
                                                    .background(restLinkedToWork ? Color.blue : Color.gray.opacity(0.15))
                                                    .foregroundStyle(restLinkedToWork ? .white : .primary)
                                                    .clipShape(Capsule())
                                                }
                                                .buttonStyle(.plain)
                                            }

                                            if restLinkedToWork {
                                                // With Shuffle on, every exercise has its own length,
                                                // so there's no single linked value to show — each
                                                // rest is half of the exercise before it.
                                                let shuffleDrivesRest = timerStyle == .standard && shuffleExerciseTime
                                                HStack(spacing: 8) {
                                                    Text(shuffleDrivesRest ? "½" : "\(effectiveRestDuration)s")
                                                        .font(.subheadline)
                                                        .fontWeight(.medium)
                                                        .padding(.horizontal, 16)
                                                        .padding(.vertical, 8)
                                                        .background(Color.blue.opacity(0.15))
                                                        .foregroundStyle(.primary)
                                                        .clipShape(Capsule())
                                                    Text(shuffleDrivesRest
                                                         ? "half of each exercise's duration"
                                                         : "half of \(exerciseDuration)s work")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                    Spacer()
                                                }
                                                .opacity(shuffleDrivesRest ? 0.4 : 1)
                                            } else {
                                                HStack(spacing: 8) {
                                                    ForEach([10, 15, 30, 60], id: \.self) { preset in
                                                        Button { restDuration = preset } label: {
                                                            Text("\(preset)s")
                                                                .font(.subheadline)
                                                                .padding(.horizontal, 16)
                                                                .padding(.vertical, 8)
                                                                .background(restDuration == preset ? Color.blue : Color.gray.opacity(0.12))
                                                                .foregroundStyle(restDuration == preset ? .white : .primary)
                                                                .clipShape(Capsule())
                                                        }
                                                        .buttonStyle(.plain)
                                                    }
                                                    Spacer()
                                                }
                                            }
                                        }

                                        // Rest Frequency — Standard only. Ladder styles always
                                        // rest after every exercise.
                                        if timerStyle == .standard {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text("Rest Frequency")
                                                    .font(.subheadline)
                                                Spacer()
                                                Text(restEvery == 1 ? "After each" : "Every \(restEvery)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            HStack(spacing: 8) {
                                                ForEach([1, 2, 3, 4, 5], id: \.self) { n in
                                                    Button { restEvery = n } label: {
                                                        Text("\(n)")
                                                            .font(.subheadline)
                                                            .fontWeight(.medium)
                                                            .frame(width: 44, height: 36)
                                                            .background(restEvery == n ? Color.blue : Color.gray.opacity(0.12))
                                                            .foregroundStyle(restEvery == n ? .white : .primary)
                                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                                Spacer()
                                            }
                                            Text("Exercises before each rest break")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        }
                                    }
                                }
                            }
                        }

                        // Warm-Up & Cool-Down — applies to every timer style, so it sits
                        // outside the Durations section (which Blocks doesn't show).
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Warm-Up & Cool-Down")
                                .font(.title2)
                                .fontWeight(.semibold)

                            Toggle(isOn: $settings.addWarmUp) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Add warm-up")
                                        .font(.subheadline)
                                    Text("About a tenth of your workout (\(warmUpSummary)), matched to your focus areas")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Toggle(isOn: $settings.addCoolDown) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Add cool-down")
                                        .font(.subheadline)
                                    Text("Two focus-relevant stretches at the end (\(coolDownSummary))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        // Block Configuration follows the Timer Style picker out of Advanced:
                        // it is the only place a Blocks routine's work durations and cycle count
                        // can be set, so hiding it would leave the style unconfigurable.
                        if timerStyle == .blocks {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Block Configuration")
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                VStack(spacing: 15) {
                                    // Number of blocks
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Number of Blocks")
                                            .font(.subheadline)
                                        HStack(spacing: 16) {
                                            ForEach([2, 3, 4], id: \.self) { n in
                                                HStack(spacing: 4) {
                                                    Image(systemName: blocksCount == n ? "circle.fill" : "circle")
                                                        .foregroundStyle(blocksCount == n ? .blue : .secondary)
                                                    Text("\(n)")
                                                        .font(.subheadline)
                                                }
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    let presets = [30, 40, 50, 60]
                                                    blocksCount = n
                                                    blockDurations = (0..<n).map { i in
                                                        blockDurations.indices.contains(i) ? blockDurations[i] : presets[i % presets.count]
                                                    }
                                                    clampBlocksTotalSets()
                                                }
                                            }
                                        }
                                    }

                                    // Exercises per block
                                    HStack {
                                        Text("Exercises per Block")
                                            .font(.subheadline)
                                        Spacer()
                                        Stepper(value: $settings.exercisesPerBlock, in: 2...5) {
                                            EmptyView()
                                        }
                                        .labelsHidden()
                                        .onChange(of: exercisesPerBlock) { _, _ in clampBlocksTotalSets() }
                                        Text("\(exercisesPerBlock)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .frame(minWidth: 24, alignment: .trailing)
                                    }

                                    // Per-block work durations
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Work Duration per Block (rest = half)")
                                            .font(.subheadline)
                                        let durationPresets = [20, 25, 30, 35, 40, 45, 50, 60]
                                        ForEach(0..<blocksCount, id: \.self) { i in
                                            HStack {
                                                Text("Block \(i + 1)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 55, alignment: .leading)
                                                Picker("Block \(i + 1)", selection: Binding(
                                                    get: { blockDurations.indices.contains(i) ? blockDurations[i] : 30 },
                                                    set: { newVal in
                                                        var updated = blockDurations
                                                        if updated.indices.contains(i) { updated[i] = newVal }
                                                        blockDurations = updated
                                                        clampBlocksTotalSets()
                                                    }
                                                )) {
                                                    ForEach(durationPresets, id: \.self) { s in
                                                        Text("\(s)s").tag(s)
                                                    }
                                                }
                                                .pickerStyle(.segmented)
                                            }
                                        }
                                    }

                                    // Total workout picker
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("Total Workout")
                                                .font(.subheadline)
                                            Spacer()
                                            Text(formatBlockTime(blocksTotalSeconds))
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        Picker("Total Workout", selection: $settings.blocksTotalSets) {
                                            ForEach(blocksAvailableTotalSets, id: \.self) { n in
                                                Text("\(n)× cycle · \(formatBlockTime(blocksTotalSeconds(forSets: n)))")
                                                    .tag(n)
                                            }
                                        }
                                        #if os(iOS)
                                        .pickerStyle(.wheel)
                                        .frame(height: 100)
                                        #endif
                                    }

                                    // Shuffle option (only meaningful when sets > 1)
                                    if blocksTotalSets > 1 {
                                        Toggle(isOn: $settings.shuffleBlockSets) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Shuffle order each set")
                                                    .font(.subheadline)
                                                Text("Re-randomize exercise order every cycle")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }

                                        // Rest Between Cycles — the longer recovery before the
                                        // whole block of exercises repeats, distinct from the
                                        // short rest between exercises within one cycle.
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text("Rest Between Cycles")
                                                    .font(.subheadline)
                                                Spacer()
                                                Button {
                                                    if blocksCycleRestLinked { blocksCycleRestDuration = effectiveBlocksCycleRest }
                                                    withAnimation(.easeInOut(duration: 0.15)) {
                                                        blocksCycleRestLinked.toggle()
                                                    }
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: blocksCycleRestLinked ? "link" : "link.badge.plus")
                                                        Text(blocksCycleRestLinked ? "Linked" : "Manual")
                                                    }
                                                    .font(.caption)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 5)
                                                    .background(blocksCycleRestLinked ? Color.blue : Color.gray.opacity(0.15))
                                                    .foregroundStyle(blocksCycleRestLinked ? .white : .primary)
                                                    .clipShape(Capsule())
                                                }
                                                .buttonStyle(.plain)
                                            }

                                            if blocksCycleRestLinked {
                                                Text("\(effectiveBlocksCycleRest)s — same as the rest between exercises")
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                    .foregroundStyle(.secondary)
                                            } else {
                                                Stepper(value: $settings.blocksCycleRestDuration, in: 5...300, step: 5) {
                                                    HStack {
                                                        Text("\(blocksCycleRestDuration)s")
                                                            .font(.subheadline)
                                                            .fontWeight(.medium)
                                                        Spacer()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                    // Back to Generate — completes the loop with the Timer card on that screen.
                    Button { onOpenGenerate?() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.footnote.weight(.semibold))
                            Text("Back to Generate")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.top, 4)
                }
                .padding()
            }
            .navigationTitle("Timer")
        }
    }

    /// Describes the pyramid that will actually run. Generated from the plan rather than
    /// hardcoded, so it can never drift out of step with the timer.
    ///
    /// The work values render as one wrapping sequence rather than a bullet per step: a 24-step
    /// pass listed line-by-line filled the entire screen and pushed Total Duration out of view.
    @ViewBuilder
    private var pyramidExplainer: some View {
        let plan = pyramidPlan
        let repeatNote = plan.repeats == 1 ? "" : ", repeated \(plan.repeats)×"
        let headline = "A \(plan.pass.count)-step climb\(repeatNote), sized to your \(totalDuration) minute total. Rest is always half the work."
        let sequence = plan.pass.map { "\($0)s" }.joined(separator: " · ")
        VStack(alignment: .leading, spacing: 6) {
            Text(headline)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(sequence)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Peaks at \(plan.pass.max() ?? 0)s work + \(WorkoutTiming.restSeconds(forWork: plan.pass.max() ?? 0))s rest  •  Total \(formatBlockTime(plan.totalSeconds))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
