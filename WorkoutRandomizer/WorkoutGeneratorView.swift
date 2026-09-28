//  WorkoutGeneratorView.swift
//  Bodyweight WorkoutRandomizer
//
//  The main generator screen: focus/equipment/difficulty selection, timing config, and routine generation.
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

struct WorkoutGeneratorView: View {
    @State private var selectedFocusAreas: Set<String> = []
    @State private var selectedDifficulties: Set<String> = ["Beginner", "Medium", "Hard", "Expert/Advanced"]
    @State private var totalDuration = 10
    @State private var exerciseDuration = 20
    /// The manually-chosen rest, used only when the link to exercise duration is off.
    @State private var restDuration = 10
    /// When on, rest is derived from exercise duration instead of set by hand.
    @AppStorage("restLinkedToWork") private var restLinkedToWork = true
    @State private var restEvery = 1
    @State private var shuffleExerciseTime = false
    @State private var generatedRoutine: [Exercise] = []
    @State private var showingWorkout = false
    @State private var isGenerating = false
    @State private var scrollToGeneratedToken = UUID()
    @State private var showingImportExport = false
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var exportDocument: WorkoutDocument?
    
    // Feedback settings — @AppStorage, not @State, so they survive a launch. Same keys as
    // SettingsView, which is how a change made there reaches the player.
    @AppStorage("enableSound_iOS_tv_vision") private var enableSound_iOS_tv_vision = true
    @AppStorage("enableHaptics_iOS_vision") private var enableHaptics_iOS_vision = true
    @AppStorage("enableSound_macOS") private var enableSound_macOS = true
    
    @State private var selectedEquipment: Set<String> = ["None"]
    @State private var timerStyle: TimerStyle = .standard
    @State private var selectedIntention: WorkoutIntention = .generalFitness
    /// Last app version the user was walked through. Empty means never — which covers a fresh
    /// install *and* anyone arriving from a build that predates this tracking, so every 1.x
    /// user gets the full 2.0 tour.
    @AppStorage("lastSeenTutorialVersion") private var lastSeenTutorialVersion = ""
    /// The guide and Settings share one presentation. They used to be two independent `.sheet`
    /// modifiers, and on a first launch the video-mode dialog and the guide both went up in the
    /// same pass — SwiftUI presented one, silently swallowed the other, and then refused every
    /// later sheet ("only presenting a single sheet is supported"), which is what made the
    /// Settings button do nothing until the app was force-quit.
    @State private var activeSheet: ActiveSheet? = nil
    /// Set by Settings when the user asks for the guide; acted on once Settings has closed.
    @State private var showGuideRequest = false
    /// The launch-time decision runs once, not on every return to this tab.
    @State private var didEvaluateGuide = false

    private enum ActiveSheet: Identifiable, Equatable {
        case guide(TutorialView.Mode)
        case settings
        case intentionInfo

        var id: String {
            switch self {
            case .guide(let mode): return "guide-\(mode.id)"
            case .settings: return "settings"
            case .intentionInfo: return "intentionInfo"
            }
        }
    }
    @State private var customExerciseStore = CustomExerciseStore.shared
    @State private var favorites = FavoritesStore.shared
    @State private var favoritesOnly = false
    @State private var showCustomTimers = false
    @State private var exerciseDurationOverrides: [Int: Int] = [:]
    @State private var showSaveConfirmation = false
    /// Routine indices where each ladder round begins; empty for non-ladder styles.
    @State private var ladderRoundStarts: [Int] = []
    @AppStorage("addWarmUp") private var addWarmUp = false
    @AppStorage("addCoolDown") private var addCoolDown = false

    @StateObject private var videoManager = VideoManager.shared
    @State private var catalog = ExerciseCatalog.shared
    @AppStorage("videoMode") private var videoModeRaw: String = VideoMode.stream.rawValue
    @State private var showVideoModePrompt = false
    @State private var downloadProgress: (completed: Int, total: Int)? = nil
    
    var focusAreas: [String] { catalog.focusAreas }
    var difficulties: [String] { catalog.difficulties }
    var exercises: [String: [String: [Exercise]]] { catalog.exercises }
    private var allEquipmentOptions: [String] { ["None", "Ab Roller", "Chair/Box/Bench"] }

    private static let stretchKeywords = ["Stretch", "Recovery", "Cool Down", "Warm-Up"]
    var workoutFocusAreas: [String] {
        focusAreas.filter { area in
            !Self.stretchKeywords.contains { area.contains($0) }
        }
    }

    private struct QuickFilter {
        let label: String
        let icon: String
        let keywordsAny: [String]
        let keywordsExclude: [String]
        let color: Color
        func areas(_ all: [String]) -> Set<String> {
            Set(all.filter { a in
                let lower = a.lowercased()
                return keywordsAny.contains { lower.contains($0) }
                    && !keywordsExclude.contains { lower.contains($0) }
            })
        }
    }

    private var quickFilters: [QuickFilter] {
        [
            // "All" matched via special-case toggle logic
            QuickFilter(label: "All", icon: "figure.mixed.cardio",
                        keywordsAny: workoutFocusAreas.map { $0.lowercased() }, keywordsExclude: [], color: .blue),
            // Selects the dedicated "Cardio" focus area; generateWorkout() also folds in
            // exercises cross-tagged additionalCategories: ["Cardio"] from other areas.
            QuickFilter(label: "Cardio", icon: "heart.fill",
                        keywordsAny: ["cardio"], keywordsExclude: [], color: .red),
            QuickFilter(label: "Core", icon: "figure.core.training",
                        keywordsAny: ["core"], keywordsExclude: [], color: .orange),
            QuickFilter(label: "Upper", icon: "figure.arms.open",
                        keywordsAny: ["upper", "arm", "shoulder", "chest", "back", "tricep", "bicep"], keywordsExclude: [], color: .purple),
            QuickFilter(label: "Lower", icon: "figure.walk",
                        keywordsAny: ["leg", "lower", "glute", "squat", "hip"], keywordsExclude: [], color: .green),
        ]
    }

    private func isFilterActive(_ filter: QuickFilter) -> Bool {
        let areas = filter.areas(workoutFocusAreas)
        if filter.label == "All" { return selectedFocusAreas.count == workoutFocusAreas.count }
        return !areas.isEmpty && areas.isSubset(of: selectedFocusAreas)
    }

    private func toggleFilter(_ filter: QuickFilter) {
        let areas = filter.areas(workoutFocusAreas)
        if filter.label == "All" {
            selectedFocusAreas = selectedFocusAreas.count == workoutFocusAreas.count
                ? [] : Set(workoutFocusAreas)
        } else if areas.isSubset(of: selectedFocusAreas) {
            selectedFocusAreas.subtract(areas)
        } else {
            selectedFocusAreas.formUnion(areas)
        }
    }

    private func equipmentIcon(_ item: String) -> String {
        switch item {
        case "None": return "nosign"
        case "Ab Roller": return "circle.dotted.circle"
        default: return "chair"
        }
    }

    private func equipmentLabel(_ item: String) -> String {
        switch item {
        case "Chair/Box/Bench": return "Chair / Box"
        default: return item
        }
    }

    @ViewBuilder
    private var focusAreaFilterRow: some View {
        OverflowScrollRow(items: quickFilters) { filter in
            Button { toggleFilter(filter) } label: {
                HStack(spacing: 5) {
                    Image(systemName: filter.icon)
                    Text(filter.label)
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isFilterActive(filter) ? filter.color : Color.gray.opacity(0.15))
                .foregroundStyle(isFilterActive(filter) ? .white : .primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var difficultyFilterRow: some View {
        OverflowScrollRow(items: difficulties) { level in
            Button {
                if selectedDifficulties.contains(level) {
                    selectedDifficulties.remove(level)
                } else {
                    selectedDifficulties.insert(level)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: difficultyIcon(level))
                    Text(level)
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selectedDifficulties.contains(level) ? Color.blue : Color.gray.opacity(0.15))
                .foregroundStyle(selectedDifficulties.contains(level) ? .white : .primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var generateButtonIsReady: Bool {
        !selectedFocusAreas.isEmpty && !selectedDifficulties.isEmpty
    }

    private func difficultyIcon(_ level: String) -> String {
        switch level {
        case "Beginner": return "1.circle.fill"
        case "Medium": return "2.circle.fill"
        case "Hard": return "3.circle.fill"
        case "Expert/Advanced": return "4.circle.fill"
        default: return "circle.fill"
        }
    }

    // Repeating Blocks state
    @State private var blocksCount: Int = 3
    @State private var exercisesPerBlock: Int = 3
    @State private var blockDurations: [Int] = [30, 25, 45]
    @State private var blocksTotalSets: Int = 2
    @State private var shuffleBlockSets: Bool = false
    /// Linked (default): the rest between full cycles is the same derived value as the rest
    /// after any other exercise — i.e. no change from before this existed. Manual: a longer,
    /// hand-picked rest before the whole block of exercises repeats.
    @State private var blocksCycleRestLinked: Bool = true
    @State private var blocksCycleRestDuration: Int = 60
    /// Off (default): an exercise keeps the same duration on both sides of the climb — the
    /// exercise assigned to the first 20s rung is also the one at the mirrored 20s rung on the
    /// way down. On: each rung gets its own independent pick, so that pairing isn't guaranteed.
    @State private var shufflePyramidOrder: Bool = false

    /// Work + derived rest for one pass through every block.
    var blocksSuperSetSeconds: Int {
        blockDurations.reduce(0) { total, work in
            total + exercisesPerBlock * (work + WorkoutTiming.restSeconds(forWork: work))
        }
    }
    /// The routine has no trailing rest after its final exercise, so the honest total is one
    /// rest shorter than the raw cycle arithmetic suggests.
    private var blocksTrailingRestSeconds: Int {
        guard let lastWork = blockDurations.last else { return 0 }
        return WorkoutTiming.restSeconds(forWork: lastWork)
    }
    /// The rest Blocks actually uses between full cycles: derived from the last block's work
    /// while linked, the hand-picked value otherwise. Everything downstream — the timing
    /// resolver and the length estimate below — must read this, never `blocksCycleRestDuration`.
    var effectiveBlocksCycleRest: Int {
        blocksCycleRestLinked ? blocksTrailingRestSeconds : blocksCycleRestDuration
    }
    func blocksTotalSeconds(forSets sets: Int) -> Int {
        guard sets > 0 else { return 0 }
        let workPerCycle = blockDurations.reduce(0) { $0 + exercisesPerBlock * $1 }
        let intraRestPerCycle = blocksSuperSetSeconds - workPerCycle - blocksTrailingRestSeconds
        let cycleGaps = max(0, sets - 1) * effectiveBlocksCycleRest
        return max(0, sets * (workPerCycle + intraRestPerCycle) + cycleGaps)
    }
    var blocksAvailableTotalSets: [Int] {
        guard blocksSuperSetSeconds > 0 else { return [1] }
        var options: [Int] = []
        var n = 1
        while blocksTotalSeconds(forSets: n) <= 90 * 60 { options.append(n); n += 1 }
        return options.isEmpty ? [1] : options
    }
    var blocksTotalSeconds: Int { blocksTotalSeconds(forSets: blocksTotalSets) }

    /// The rest that Standard routines actually use: derived from exercise duration while the
    /// link is on, the hand-picked value otherwise. Everything downstream — the timing resolver,
    /// the player, export, the routine-length estimate — must read this, never `restDuration`.
    var effectiveRestDuration: Int {
        restLinkedToWork ? WorkoutTiming.restSeconds(forWork: exerciseDuration) : restDuration
    }

    private func clampBlocksTotalSets() {
        let options = blocksAvailableTotalSets
        if !options.contains(blocksTotalSets) { blocksTotalSets = options.first ?? 1 }
    }

    /// The one place timing rules live. Built fresh from current state so the Custom Timers
    /// editor and the player always agree about how long a given slot runs.
    var timing: WorkoutTiming {
        WorkoutTiming(
            style: timerStyle,
            exerciseDuration: exerciseDuration,
            restDuration: effectiveRestDuration,
            blocksConfig: timerStyle == .blocks
                ? RepeatingBlocksConfig(
                    exercisesPerBlock: exercisesPerBlock,
                    blockDurations: blockDurations,
                    cycleRestSeconds: blocksTotalSets > 1 ? effectiveBlocksCycleRest : nil
                  )
                : nil,
            overrides: exerciseDurationOverrides,
            pyramidLadder: pyramidPlan.ladder
        )
    }

    /// Human-readable size of the warm-up that would be added at the current total duration.
    var warmUpSummary: String {
        let targetSeconds = max(Self.warmUpSecondsPerMove, totalDuration * 60 / 10)
        let moves = min(8, max(1, targetSeconds / Self.warmUpSecondsPerMove))
        return "\(moves) × \(Self.warmUpSecondsPerMove)s"
    }

    var coolDownSummary: String {
        "\(Self.coolDownHoldCount) × \(Self.coolDownSecondsPerHold)s"
    }

    /// The pyramid sized for the currently-selected total duration.
    var pyramidPlan: WorkoutTiming.PyramidPlan {
        WorkoutTiming.pyramidPlan(forTotalMinutes: totalDuration)
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
    private func formatBlockTime(_ seconds: Int) -> String {
        let m = seconds / 60; let s = seconds % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        
                        // Focus Areas
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Focus Areas")
                                .font(.title2)
                                .fontWeight(.semibold)

                            // Quick filters — multi-select: tap to toggle each group
                            focusAreaFilterRow

                        }
                        .id("focusAreasSection")

                        // Equipment Available
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Equipment Available")
                                .font(.title2)
                                .fontWeight(.semibold)

                            HStack(spacing: 10) {
                                ForEach(allEquipmentOptions, id: \.self) { item in
                                    Button {
                                        if selectedEquipment.contains(item) {
                                            selectedEquipment.remove(item)
                                        } else {
                                            selectedEquipment.insert(item)
                                        }
                                    } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: equipmentIcon(item))
                                                .font(.title2)
                                            Text(equipmentLabel(item))
                                                .font(.caption2)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(selectedEquipment.contains(item) ? Color.blue : Color.gray.opacity(0.1))
                                        .foregroundStyle(selectedEquipment.contains(item) ? .white : .primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Difficulty — multi-select: tap to toggle each level
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Difficulty")
                                .font(.title2)
                                .fontWeight(.semibold)

                            difficultyFilterRow
                        }
                        .id("difficultySection")

                        // Favorites — restrict the pool to starred exercises only
                        if !favorites.names.isEmpty {
                            Toggle(isOn: $favoritesOnly) {
                                HStack(spacing: 8) {
                                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                                        .foregroundStyle(.yellow)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Favorites Only")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text("Only use exercises you've starred on the Exercises tab")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .toggleStyle(.switch)
                        }

                        // Intention — single-select icon chips
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 6) {
                                Text("Intention")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Button {
                                    activeSheet = .intentionInfo
                                } label: {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 10) {
                                ForEach(WorkoutIntention.allCases) { intent in
                                    Button { selectedIntention = intent } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: intent.icon)
                                                .font(.title2)
                                            Text(intent.rawValue)
                                                .font(.caption)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(selectedIntention == intent ? intent.bannerColor : Color.gray.opacity(0.1))
                                        .foregroundStyle(selectedIntention == intent ? .white : .primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

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

                                Toggle(isOn: $shufflePyramidOrder) {
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
                                        // Exercise Duration presets
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
                                                Spacer()
                                            }
                                        }

                                        // Shuffle Exercise Time — Standard only. Gives each work
                                        // slot its own random pick from the same presets above
                                        // instead of one fixed value for every exercise. The same
                                        // result can already be built by hand with Custom Timers;
                                        // this just automates it.
                                        if timerStyle == .standard {
                                            Toggle(isOn: $shuffleExerciseTime) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("Shuffle Exercise Time")
                                                        .font(.subheadline)
                                                    Text("Each exercise gets its own random duration instead of one fixed length")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
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
                                                HStack(spacing: 8) {
                                                    Text("\(effectiveRestDuration)s")
                                                        .font(.subheadline)
                                                        .fontWeight(.medium)
                                                        .padding(.horizontal, 16)
                                                        .padding(.vertical, 8)
                                                        .background(Color.blue.opacity(0.15))
                                                        .foregroundStyle(.primary)
                                                        .clipShape(Capsule())
                                                    Text("half of \(exerciseDuration)s work")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                    Spacer()
                                                }
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

                            Toggle(isOn: $addWarmUp) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Add warm-up")
                                        .font(.subheadline)
                                    Text("About a tenth of your workout (\(warmUpSummary)), matched to your focus areas")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Toggle(isOn: $addCoolDown) {
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
                                        Stepper(value: $exercisesPerBlock, in: 2...5) {
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
                                        Picker("Total Workout", selection: $blocksTotalSets) {
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
                                        Toggle(isOn: $shuffleBlockSets) {
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
                                                Stepper(value: $blocksCycleRestDuration, in: 5...300, step: 5) {
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


                        // Generate Button
                        Button {
                            if selectedFocusAreas.isEmpty {
                                withAnimation { proxy.scrollTo("focusAreasSection", anchor: .top) }
                            } else if selectedDifficulties.isEmpty {
                                withAnimation { proxy.scrollTo("difficultySection", anchor: .top) }
                            } else {
                                generateWorkout()
                                // Attempt to auto-scroll to the generated section after state updates
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    withAnimation {
                                        proxy.scrollTo(scrollToGeneratedToken, anchor: .top)
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                if isGenerating {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Generating workout...")
                                } else if selectedFocusAreas.isEmpty {
                                    Text("Focus Area(s) must be selected")
                                } else if selectedDifficulties.isEmpty {
                                    Text("Difficulty must be selected")
                                } else {
                                    Text("Generate Workout")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(generateButtonIsReady ? Color.blue : Color.gray.opacity(0.3))
                            .foregroundStyle(generateButtonIsReady ? .white : .secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(isGenerating)
                        
                        if !generatedRoutine.isEmpty {
                            Text("Workout generated below")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        
                        // Generated Routine
                        if !generatedRoutine.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Generated Routine")
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showCustomTimers.toggle()
                                            if !showCustomTimers { exerciseDurationOverrides.removeAll() }
                                        }
                                    } label: {
                                            Label(showCustomTimers ? "Timers On" : "Custom Timers",
                                                  systemImage: showCustomTimers ? "timer.circle.fill" : "timer.circle")
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(showCustomTimers ? Color.blue : Color.gray.opacity(0.15))
                                                .foregroundStyle(showCustomTimers ? .white : .primary)
                                                .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }

                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(generatedRoutine.enumerated()), id: \.offset) { index, exercise in
                                        HStack {
                                            Text("\(index + 1).")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .frame(width: 30, alignment: .leading)
                                            Text(exercise.name)
                                                .font(.subheadline)
                                            Spacer()
                                            if showCustomTimers && exercise.name != "Rest" {
                                                HStack(spacing: 4) {
                                                    Text("\(timing.duration(at: index, in: generatedRoutine))s")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .frame(minWidth: 32, alignment: .trailing)
                                                    Stepper(
                                                        value: Binding(
                                                            get: { timing.duration(at: index, in: generatedRoutine) },
                                                            set: { exerciseDurationOverrides[index] = $0 }
                                                        ),
                                                        in: 5...300, step: 5
                                                    ) { EmptyView() }
                                                    .labelsHidden()
                                                }
                                            } else if showCustomTimers && exercise.name == "Rest" {
                                                HStack(spacing: 4) {
                                                    Text("\(timing.duration(at: index, in: generatedRoutine))s")
                                                        .font(.caption)
                                                        .foregroundStyle(.blue)
                                                        .frame(minWidth: 32, alignment: .trailing)
                                                    Stepper(
                                                        value: Binding(
                                                            get: { timing.duration(at: index, in: generatedRoutine) },
                                                            set: { exerciseDurationOverrides[index] = $0 }
                                                        ),
                                                        in: 5...300, step: 5
                                                    ) { EmptyView() }
                                                    .labelsHidden()
                                                }
                                            }

                                            // Reorder/delete — disabled for ladder styles (Add-On,
                                            // Add-On + Take Away), whose round structure is derived
                                            // from the generated sequence itself and would desync
                                            // from a manual edit.
                                            if !timerStyle.isLadder {
                                                HStack(spacing: 10) {
                                                    Button {
                                                        moveRoutineItem(at: index, offset: -1)
                                                    } label: {
                                                        Image(systemName: "chevron.up")
                                                    }
                                                    .disabled(index == 0)

                                                    Button {
                                                        moveRoutineItem(at: index, offset: 1)
                                                    } label: {
                                                        Image(systemName: "chevron.down")
                                                    }
                                                    .disabled(index == generatedRoutine.count - 1)

                                                    Button(role: .destructive) {
                                                        deleteRoutineItem(at: index)
                                                    } label: {
                                                        Image(systemName: "trash")
                                                    }
                                                }
                                                .font(.caption)
                                                .buttonStyle(.plain)
                                                .foregroundStyle(.secondary)
                                                .padding(.leading, 6)
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                                .padding()
                                .background(.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                
                                VStack(spacing: 8) {
                                    Button {
                                        showingWorkout = true
                                    } label: {
                                        HStack {
                                            Image(systemName: "play.fill")
                                            Text("Start Workout")
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(.green)
                                        .foregroundStyle(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }

                                    HStack(spacing: 8) {
                                        Button {
                                            exportWorkout()
                                        } label: {
                                            HStack {
                                                Image(systemName: "square.and.arrow.up")
                                                Text("Export")
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(.blue)
                                            .foregroundStyle(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                        }

                                        Button {
                                            saveGeneratedRoutine()
                                        } label: {
                                            HStack {
                                                Image(systemName: "bookmark.fill")
                                                Text("Save")
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(.purple)
                                            .foregroundStyle(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                    }
                                }
                            }
                            .id(scrollToGeneratedToken)
                        }
                        
                        // Import Workout Button
                        if generatedRoutine.isEmpty {
                            Button {
                                showingImporter = true
                            } label: {
                                HStack {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Import Workout")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.purple)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Workout Generator")
            .toolbar {
#if os(iOS) || os(visionOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { activeSheet = .settings } label: {
                        Label("Settings", systemImage: "gearshape")
                            .labelStyle(.iconOnly)
                    }
                }
#else
                ToolbarItem {
                    Button { activeSheet = .settings } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
#endif
            }
        }
        .sheet(isPresented: $showingWorkout) {
            WorkoutPlayerView(
                routine: generatedRoutine,
                // The same value the Custom Timers editor reads, so the preview and the clock
                // are guaranteed to agree.
                timing: timing,
                intention: selectedIntention,
                selectedFocusAreas: selectedFocusAreas,
                enableSound_iOS_tv_vision: enableSound_iOS_tv_vision,
                enableHaptics_iOS_vision: enableHaptics_iOS_vision,
                enableSound_macOS: enableSound_macOS,
                ladderRoundStarts: ladderRoundStarts.isEmpty ? nil : ladderRoundStarts
            )
            // A stray scroll/swipe shouldn't be able to abruptly end an active routine —
            // stopping now requires the confirmed Stop button inside the player.
            .interactiveDismissDisabled(true)
        }
        // One sheet for the guide and Settings, so the two can never both try to present.
        // Whatever should follow a dismissal is decided in onDismiss rather than by setting a
        // second flag alongside the first.
        .sheet(item: $activeSheet, onDismiss: {
            if showGuideRequest {
                showGuideRequest = false
                activeSheet = .guide(.full)
            } else {
                promptForVideoModeIfNeeded()
            }
        }) { sheet in
            switch sheet {
            case .guide(let mode):
                TutorialView(mode: mode)
            case .settings:
                SettingsView(showGuideRequest: $showGuideRequest)
            case .intentionInfo:
                IntentionInfoView()
            }
        }
        .alert("Routine Saved", isPresented: $showSaveConfirmation) {
            Button("OK") { }
        } message: {
            Text("This workout has been added to My Routines in the Saved Routines tab.")
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "workout.json",
            onCompletion: { result in
                switch result {
                case .success(let url):
                    print("Workout exported to: \(url)")
                case .failure(let error):
                    print("Export failed: \(error.localizedDescription)")
                }
                exportDocument = nil
            }
        )
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                do {
                    let data = try Data(contentsOf: url)
                    let exercises = try JSONDecoder().decode([ExportableExercise].self, from: data)
                    let document = WorkoutDocument(exercises: exercises)
                    importWorkout(from: document)
                } catch {
                    print("Import failed: \(error.localizedDescription)")
                }
            case .failure(let error):
                print("File selection failed: \(error.localizedDescription)")
            }
        }
        .onAppear {
            // The guide goes first and the video-mode prompt follows it, which is both the only
            // safe order and the better one: the Audio, Video & Settings page explains the
            // choice immediately before it gets asked.
            if !didEvaluateGuide {
                didEvaluateGuide = true
                if let mode = pendingGuideMode() {
                    activeSheet = .guide(mode)
                    return
                }
            }
            promptForVideoModeIfNeeded()
        }
        .task {
            await catalog.refresh()
        }
        .confirmationDialog("Select Video Mode", isPresented: $showVideoModePrompt, titleVisibility: .visible) {
            Button(VideoMode.downloadOnFirstLaunch.rawValue) {
                videoModeRaw = VideoMode.downloadOnFirstLaunch.rawValue
                videoManager.videoMode = videoModeRaw
                videoManager.didPromptForVideoMode = true
                startVideoDownload()
            }
            Button(VideoMode.stream.rawValue) {
                videoModeRaw = VideoMode.stream.rawValue
                videoManager.videoMode = videoModeRaw
                videoManager.didPromptForVideoMode = true
            }
            Button(VideoMode.none.rawValue) {
                videoModeRaw = VideoMode.none.rawValue
                videoManager.videoMode = videoModeRaw
                videoManager.didPromptForVideoMode = true
            }
            Button("Cancel", role: .cancel) { }
        }
        .overlay(alignment: .center) {
            if let progress = downloadProgress {
                Color.black.opacity(0.4)
                    .cornerRadius(10)
                    .padding()
                    .overlay {
                        VStack(spacing: 20) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(1.5)
                            Text("Downloading videos \(progress.completed) of \(progress.total)")
                                .foregroundStyle(.white)
                                .font(.headline)
                            Button("Cancel") {
                                VideoManager.shared.cancelAllDownloads()
                                downloadProgress = nil
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                        .padding(30)
                    }
            }
        }
    }
    
    /// Kicked off by the first-launch video-mode prompt. Settings has its own button for the
    /// same job; both go through VideoManager so the key list is assembled in one place.
    private func startVideoDownload() {
        downloadProgress = (completed: 0, total: videoManager.videoPaths.count)
        videoManager.downloadAllKnownVideos(progress: { completed, total in
            downloadProgress = (completed: completed, total: total)
        }, completion: {
            downloadProgress = nil
        })
    }
    
    /// Which run of the guide, if any, this launch owes the user.
    ///
    /// Nothing recorded means the full tour — a first install, or an upgrade from a build that
    /// predated this tracking. Otherwise only a genuinely newer version earns a "what's new",
    /// and only when there are pages tagged for it: a release that documents nothing new should
    /// pass in silence rather than open an empty guide.
    private func pendingGuideMode() -> TutorialView.Mode? {
        guard !lastSeenTutorialVersion.isEmpty else { return .full }
        guard AppVersion.isNewer(AppVersion.current, than: lastSeenTutorialVersion),
              TutorialView.hasPages(newerThan: lastSeenTutorialVersion) else { return nil }
        return .whatsNew(since: lastSeenTutorialVersion)
    }

    /// Ask which video mode to use, but never while something else is on screen.
    private func promptForVideoModeIfNeeded() {
        guard activeSheet == nil, !videoManager.didPromptForVideoMode else { return }
        showVideoModePrompt = true
    }

    private func generateWorkout() {
        isGenerating = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let allowedLevels = Array(selectedDifficulties)
            var pool: [Exercise] = []

            // Build exercise pool, filtered by selected equipment
            for area in selectedFocusAreas {
                for level in allowedLevels {
                    if let areaExercises = exercises[area],
                       let levelExercises = areaExercises[level] {
                        let available = levelExercises.filter { ex in
                            ex.equipment.contains { selectedEquipment.contains($0) }
                        }
                        pool.append(contentsOf: available)
                    }
                }
            }

            // Cardio bonus: fold in exercises cross-tagged additionalCategories: ["Cardio"]
            // from other focus areas (e.g. Squat Jumps under Legs, Mountain Climbers under
            // Core) even when that area isn't itself selected — mirrors how stretch routines
            // pull secondary-category exercises via exercisesByAdditionalCategory.
            if selectedFocusAreas.contains("Cardio") {
                let poolNames = Set(pool.map { $0.name })
                let cardioByLevel = catalog.exercisesByAdditionalCategoryAndDifficulty["Cardio"] ?? [:]
                for level in allowedLevels {
                    guard let levelExercises = cardioByLevel[level] else { continue }
                    let available = levelExercises.filter { ex in
                        !poolNames.contains(ex.name) && ex.equipment.contains { selectedEquipment.contains($0) }
                    }
                    pool.append(contentsOf: available)
                }
            }

            // Merge user-defined custom exercises
            for custom in customExerciseStore.exercises {
                if selectedFocusAreas.contains(custom.focusArea) && allowedLevels.contains(custom.difficulty) && selectedEquipment.contains("None") {
                    pool.append(Exercise(name: custom.name, videoPath: nil, equipment: ["None"]))
                }
            }

            if favoritesOnly {
                pool = pool.filter { favorites.isFavorite($0.name) }
            }

            guard !pool.isEmpty else {
                isGenerating = false
                return
            }

            // Ladder styles build their own round structure from distinct rungs, so they skip
            // the flat maxExercises/createBalancedRoutine path entirely.
            if timerStyle.isLadder {
                let takeAway = timerStyle == .addOnTakeAway
                // A ladder beyond ~10 rungs is impractical to remember, let alone perform.
                let units = ladderUnits(from: pool, maxUnits: 10)
                guard !units.isEmpty else {
                    isGenerating = false
                    return
                }
                let rungs = bestLadderRungs(units: units, takeAway: takeAway)

                var routine: [Exercise] = []
                var roundStarts: [Int] = []
                for size in ladderRoundSizes(rungs: rungs, takeAway: takeAway) {
                    roundStarts.append(routine.count)
                    for unit in units[0..<size] {
                        for exercise in unit {
                            routine.append(exercise)
                            routine.append(Exercise(name: "Rest", videoPath: nil, equipment: ["None"]))
                        }
                    }
                }
                // No trailing rest after the final exercise of the routine.
                if routine.last?.name == "Rest" { routine.removeLast() }

                publish(routine: routine, roundStarts: roundStarts)
                return
            }

            // Compute target exercise count based on timer style
            let maxExercises: Int
            switch timerStyle {
            case .pyramid:
                // One exercise per rung of the duration-derived ladder.
                maxExercises = pyramidPlan.ladder.count
            case .blocks:
                // One set's worth, not the whole session. Asking for every slot at once let
                // createBalancedRoutine fill them all with *distinct* exercises, so a style
                // named Repeating Blocks repeated nothing — the sets are built below by
                // reusing this base rather than by drawing more exercises.
                maxExercises = blocksCount * exercisesPerBlock
            case .standard:
                let fullCycle = Double(exerciseDuration) + (Double(effectiveRestDuration) / Double(restEvery))
                let totalSecs = Double(totalDuration) * 60
                maxExercises = Int(ceil(totalSecs / fullCycle))
            case .addOn, .addOnTakeAway:
                maxExercises = 0   // unreachable: ladder styles return before this point
            }

            // Create balanced routine
            let selected = createBalancedRoutine(from: pool, maxCount: maxExercises)

            // Build final routine with rests
            var routine: [Exercise] = []
            if timerStyle == .pyramid || timerStyle == .blocks {
                // Blocks runs the same base set once per total-set; shuffle only decides
                // whether each repeat keeps the base order or gets its own arrangement.
                // Previously the un-shuffled path fell through to `selected` unchanged, which
                // is why it produced one long list of unique exercises instead of repeats.
                let exercises: [Exercise]
                if timerStyle == .pyramid && !shufflePyramidOrder {
                    // Mirror the ascending half back down so an exercise keeps the same
                    // duration on both sides of the climb, matching how the durations
                    // themselves already mirror. Shuffle Order (below) skips this and lets
                    // every rung get its own independent pick instead.
                    let half = max(1, pyramidPlan.pass.count / 2)
                    exercises = (0..<pyramidPlan.repeats).flatMap { _ -> [Exercise] in
                        let ascending = Array(createBalancedRoutine(from: pool, maxCount: half).prefix(half))
                        return ascending + ascending.reversed()
                    }
                } else if timerStyle == .blocks && blocksTotalSets > 1 {
                    // The base has to be *exactly* one set long. createBalancedRoutine can
                    // overshoot by one when its last pick is single-sided and both sides land,
                    // and repeating a base of the wrong length would push every later set's
                    // block boundaries one slot further out of step.
                    var base = selected
                    if base.count > maxExercises {
                        base.removeLast(2)   // the trailing Left/Right pair, kept together
                        let used = Set(base.map { $0.name })
                        // Prefer an unused two-sided move for the freed slot; if the pool is
                        // already exhausted, repeating one beats leaving the set a slot short.
                        let fresh = pool.shuffled().first(where: { !$0.singleSided && !used.contains($0.name) })
                        let reused = base.shuffled().first(where: { !$0.name.hasSuffix(" (Left)") && !$0.name.hasSuffix(" (Right)") })
                        if let filler = fresh ?? reused { base.append(filler) }
                    }
                    // Shuffle Left/Right pairs as a single atomic unit so the two sides
                    // always stay back-to-back after shuffling.
                    let baseUnits = atomicSideUnits(base)
                    var repeated: [Exercise] = []
                    for _ in 0..<blocksTotalSets {
                        repeated.append(contentsOf: shuffleBlockSets
                                        ? baseUnits.shuffled().flatMap { $0 }
                                        : base)
                    }
                    exercises = repeated
                } else {
                    exercises = selected
                }
                // Every exercise gets its own rest (except the last)
                for (index, exercise) in exercises.enumerated() {
                    routine.append(exercise)
                    if index < exercises.count - 1 {
                        routine.append(Exercise(name: "Rest", videoPath: nil, equipment: ["None"]))
                    }
                }
            } else {
                for (index, exercise) in selected.enumerated() {
                    routine.append(exercise)
                    if ((index + 1) % restEvery == 0) && (index != selected.count - 1) {
                        routine.append(Exercise(name: "Rest", videoPath: nil, equipment: ["None"]))
                    }
                }
            }

            publish(routine: routine)
            if timerStyle == .standard && shuffleExerciseTime {
                applyShuffledExerciseTimes()
                // Otherwise the preview shows a flat list with no visible sign anything
                // was randomized — surface the per-exercise durations right away.
                showCustomTimers = true
            }
        }
    }

    /// Gives each Standard-style work slot its own randomly-picked duration from the same
    /// presets as the Exercise Duration chips, via the same override mechanism Custom Timers
    /// uses — so this is just an automated version of hand-editing every slot. Rest keeps its
    /// normal (linked-or-manual) behavior; only work varies. Runs after `publish(routine:)` so
    /// it can key off `generatedRoutine`'s final indices rather than re-deriving the warm-up
    /// offset itself.
    private func applyShuffledExerciseTimes() {
        let options = [20, 30, 45, 60]
        for (index, exercise) in generatedRoutine.enumerated() {
            guard !exercise.isPreparation, exercise.name != "Rest" else { continue }
            exerciseDurationOverrides[index] = options.randomElement() ?? exerciseDuration
        }
    }
    
    // Single-sided exercises are chosen as one slot but always expand into their
    // Left/Right pair together, so the two sides land back-to-back in the routine
    // (only a rest, never another exercise, can end up between them).
    private func expandSides(_ exercise: Exercise) -> [Exercise] {
        guard exercise.singleSided else { return [exercise] }
        let left  = Exercise(name: "\(exercise.name) (Left)",  videoPath: exercise.videoPath, equipment: exercise.equipment, isMovement: exercise.isMovement, relatedFocusAreas: exercise.relatedFocusAreas)
        let right = Exercise(name: "\(exercise.name) (Right)", videoPath: exercise.videoPath, equipment: exercise.equipment, isMovement: exercise.isMovement, relatedFocusAreas: exercise.relatedFocusAreas)
        return [left, right]
    }

    // Groups a flat exercise list into shuffle-safe units: an adjacent Left/Right
    // pair stays together as one unit, everything else is its own unit.
    private func atomicSideUnits(_ exercises: [Exercise]) -> [[Exercise]] {
        var units: [[Exercise]] = []
        var i = 0
        while i < exercises.count {
            let current = exercises[i]
            if current.name.hasSuffix(" (Left)"),
               i + 1 < exercises.count,
               exercises[i + 1].name == current.name.replacingOccurrences(of: " (Left)", with: " (Right)") {
                units.append([current, exercises[i + 1]])
                i += 2
            } else {
                units.append([current])
                i += 1
            }
        }
        return units
    }

    // MARK: - Warm-up & cool-down

    private static let warmUpCategories = ["Warm-Up: Full Body", "Warm-Up: Hips"]
    private static let coolDownCategories = ["Cool Down"]
    /// Each warm-up move runs this long; cool-down holds run longer to be worth doing.
    private static let warmUpSecondsPerMove = 30
    private static let coolDownSecondsPerHold = 30
    private static let coolDownHoldCount = 2

    /// Every stretch belonging to the given categories, whether by its own focus area or by
    /// cross-tag, deduplicated by name.
    private func preparationCandidates(categories: [String]) -> [Exercise] {
        var result: [Exercise] = []
        var seen = Set<String>()
        for category in categories {
            var found: [Exercise] = []
            if let byDifficulty = exercises[category] {
                found += byDifficulty.values.flatMap { $0 }
            }
            found += catalog.exercisesByAdditionalCategory[category] ?? []
            for exercise in found where !seen.contains(exercise.name) {
                seen.insert(exercise.name)
                result.append(exercise)
            }
        }
        return result
    }

    /// Narrow a stretch pool to the selected focus areas. An untagged stretch suits any focus,
    /// so it always stays in — that guarantees the pool is never empty, without a special case.
    private func matchingSelectedFocus(_ candidates: [Exercise]) -> [Exercise] {
        let matched = candidates.filter { exercise in
            exercise.relatedFocusAreas.isEmpty
                || !Set(exercise.relatedFocusAreas).isDisjoint(with: selectedFocusAreas)
        }
        return matched.isEmpty ? candidates : matched
    }

    /// Warm-up sized to roughly a tenth of the session — about a minute for a 10 minute
    /// workout — using stretches relevant to the focus areas selected.
    private func buildWarmUp() -> [Exercise] {
        guard addWarmUp else { return [] }
        let pool = matchingSelectedFocus(preparationCandidates(categories: Self.warmUpCategories))
        guard !pool.isEmpty else { return [] }
        let targetSeconds = max(Self.warmUpSecondsPerMove, totalDuration * 60 / 10)
        let wanted = min(8, max(1, targetSeconds / Self.warmUpSecondsPerMove))
        // Mobility flows straight through — no rests between warm-up moves.
        return pool.shuffled().prefix(wanted).map {
            var move = $0
            move.preparationDuration = Self.warmUpSecondsPerMove
            return move
        }
    }

    /// A short cool-down: a couple of focus-relevant holds. Two-sided stretches are preferred so
    /// the cool-down stays brief rather than doubling into Left/Right.
    private func buildCoolDown() -> [Exercise] {
        guard addCoolDown else { return [] }
        let pool = matchingSelectedFocus(preparationCandidates(categories: Self.coolDownCategories))
        guard !pool.isEmpty else { return [] }
        let preferred = pool.filter { !$0.singleSided }
        let chosen = (preferred.count >= Self.coolDownHoldCount ? preferred : pool)
            .shuffled().prefix(Self.coolDownHoldCount)
        return chosen.flatMap { hold -> [Exercise] in
            expandSides(hold).map {
                var side = $0
                side.preparationDuration = Self.coolDownSecondsPerHold
                return side
            }
        }
    }

    /// Wrap the generated work in its warm-up and cool-down and publish the result. Every timer
    /// style funnels through here so the wrapping — and the round-index shift it causes — is
    /// handled in exactly one place.
    private func publish(routine core: [Exercise], roundStarts: [Int] = []) {
        let warmUp = buildWarmUp()
        var routine = warmUp + core
        if !warmUp.isEmpty, let first = core.first, !first.isPreparation {
            // One breath between the warm-up and the first working set.
            var transition = Exercise(name: "Rest", videoPath: nil, equipment: ["None"])
            transition.preparationDuration = effectiveRestDuration
            routine = warmUp + [transition] + core
        }
        let offset = routine.count - core.count
        routine += buildCoolDown()

        generatedRoutine = routine
        // Round markers were computed against the un-wrapped routine, so shift them.
        ladderRoundStarts = roundStarts.map { $0 + offset }
        exerciseDurationOverrides.removeAll()
        showCustomTimers = false
        isGenerating = false
        scrollToGeneratedToken = UUID()
    }

    // MARK: - Ladder styles (Add-On / Add-On + Take Away)

    /// Distinct exercises to build a ladder from. Each rung is expanded into its Left/Right pair
    /// where needed and kept together, so a single-sided rung costs two slots rather than one.
    private func ladderUnits(from pool: [Exercise], maxUnits: Int) -> [[Exercise]] {
        var units: [[Exercise]] = []
        var seen = Set<String>()
        for exercise in pool.shuffled() {
            guard units.count < maxUnits else { break }
            guard !seen.contains(exercise.name) else { continue }
            seen.insert(exercise.name)
            units.append(expandSides(exercise))
        }
        return units
    }

    /// The round pattern for a ladder: 1…rungs ascending, then rungs-1…1 back down when the
    /// take-away variant is selected.
    private func ladderRoundSizes(rungs: Int, takeAway: Bool) -> [Int] {
        guard rungs > 0 else { return [] }
        var sizes = Array(1...rungs)
        if takeAway, rungs > 1 { sizes += Array((1..<rungs).reversed()) }
        return sizes
    }

    /// Total exercise slots a ladder of this size would run, counting single-sided rungs twice.
    private func ladderSlotCount(units: [[Exercise]], rungs: Int, takeAway: Bool) -> Int {
        ladderRoundSizes(rungs: rungs, takeAway: takeAway).reduce(0) { total, size in
            total + units[0..<size].reduce(0) { $0 + $1.count }
        }
    }

    /// Pick the ladder size whose running time lands closest to the requested total. Closest
    /// rather than largest-that-fits: asking for 10 minutes and getting 7:30 is a worse answer
    /// than getting 11:15.
    private func bestLadderRungs(units: [[Exercise]], takeAway: Bool) -> Int {
        guard !units.isEmpty else { return 0 }
        let target = totalDuration * 60
        let slotCost = exerciseDuration + effectiveRestDuration
        var best = 1
        var bestDelta = Int.max
        for rungs in 1...units.count {
            let slots = ladderSlotCount(units: units, rungs: rungs, takeAway: takeAway)
            let seconds = max(0, slots * slotCost - effectiveRestDuration)
            let delta = abs(seconds - target)
            if delta < bestDelta {
                bestDelta = delta
                best = rungs
            }
        }
        return best
    }

    private func createBalancedRoutine(from pool: [Exercise], maxCount: Int) -> [Exercise] {
        let shuffled = pool.shuffled()
        var uniqueExercises: [Exercise] = []
        var seen = Set<String>()

        // Get unique exercises first
        for exercise in shuffled {
            if !seen.contains(exercise.name) && uniqueExercises.count < maxCount {
                uniqueExercises.append(exercise)
                seen.insert(exercise.name)
            }
        }

        var result: [Exercise] = []
        for exercise in uniqueExercises {
            if result.count >= maxCount { break }
            result.append(contentsOf: expandSides(exercise))
        }

        // Fill remaining slots with repeats
        while result.count < maxCount {
            let reshuffled = uniqueExercises.shuffled()
            for exercise in reshuffled {
                if result.count >= maxCount { break }
                result.append(contentsOf: expandSides(exercise))
            }
        }

        return result
    }
    
    private func exportWorkout() {
        // Durations must come from the resolver, not the flat Standard-style values —
        // otherwise a Pyramid or Blocks routine exports with whatever exerciseDuration
        // happens to be set, and any Custom Timers edits are dropped entirely.
        let exportableExercises = generatedRoutine.enumerated().map { index, exercise in
            let isRest = exercise.name == "Rest"
            // A non-rest slot carries the rest that actually follows it; when no rest follows
            // (rest frequency > 1) fall back to the configured value, as before.
            let followingRest: Int = {
                guard !isRest else { return 0 }
                let next = index + 1
                guard next < generatedRoutine.count,
                      generatedRoutine[next].name == "Rest" else { return effectiveRestDuration }
                return timing.duration(at: next, in: generatedRoutine)
            }()
            return ExportableExercise(
                name: exercise.name,
                isTimeBased: true,
                exerciseDuration: timing.duration(at: index, in: generatedRoutine),
                restDuration: followingRest,
                sets: 1
            )
        }
        let document = WorkoutDocument(exercises: exportableExercises)
        exportDocument = document
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showingExporter = true
        }
    }
    
    private func saveGeneratedRoutine() {
        var savedExercises: [SavedRoutineExercise] = []
        for (i, ex) in generatedRoutine.enumerated() {
            if ex.name == "Rest" {
                let restDur = timing.duration(at: i, in: generatedRoutine)
                if !savedExercises.isEmpty {
                    let last = savedExercises[savedExercises.count - 1]
                    savedExercises[savedExercises.count - 1] = SavedRoutineExercise(
                        name: last.name,
                        duration: last.duration,
                        restDuration: restDur,
                        singleSided: last.singleSided,
                        moveType: last.moveType
                    )
                }
            } else {
                let dur = timing.duration(at: i, in: generatedRoutine)
                savedExercises.append(SavedRoutineExercise(
                    name: ex.name,
                    duration: dur,
                    restDuration: 0,
                    singleSided: ex.singleSided,
                    // `isMovement` is a stretch-catalog flag: it marks moving mobility drills
                    // (Cat-Cow, Arm Circles) apart from static holds (Pigeon Pose), and no
                    // workout exercise carries it at all. So it only decides the label for
                    // warm-up and cool-down slots — everything else is a movement by definition,
                    // and reading the flag for those would mislabel every push-up as a hold.
                    moveType: ex.isPreparation ? (ex.isMovement ? .move : .hold) : .move
                ))
            }
        }
        let focusLabel = selectedFocusAreas.sorted().prefix(2).joined(separator: " & ")
        let routineName = focusLabel.isEmpty ? "My Workout" : "\(focusLabel) Workout"
        let routine = SavedWorkoutRoutine(
            name: routineName,
            routineDescription: "",
            source: "My Routines",
            sourceURL: "",
            exercises: savedExercises,
            accentColorName: "purple",
            systemImage: "dumbbell.fill"
        )
        SavedRoutineStore.shared.save(routine)
        showSaveConfirmation = true
    }

    private func importWorkout(from document: WorkoutDocument) {
        var importedRoutine: [Exercise] = []
        var didSetDurations = false
        
        for exportableExercise in document.exercises {
            // Try to find matching exercise in our database
            var foundExercise: Exercise?
            
            for (_, difficultyDict) in exercises {
                for (_, exerciseList) in difficultyDict {
                    if let match = exerciseList.first(where: { $0.name == exportableExercise.name }) {
                        foundExercise = match
                        break
                    }
                }
                if foundExercise != nil { break }
            }
            
            // If found, use it; otherwise create a basic exercise with no video
            let exercise = foundExercise ?? Exercise(name: exportableExercise.name, videoPath: nil, equipment: ["None"])
            importedRoutine.append(exercise)
            
            // Update durations from the first non-rest exercise only
            if !didSetDurations && exportableExercise.isTimeBased && exportableExercise.name != "Rest" {
                exerciseDuration = exportableExercise.exerciseDuration
                if exportableExercise.restDuration > 0 {
                    // The file specifies its own rest; honour it rather than re-deriving.
                    restDuration = exportableExercise.restDuration
                    restLinkedToWork = false
                }
                didSetDurations = true
            }
        }
        
        generatedRoutine = importedRoutine
        scrollToGeneratedToken = UUID()
    }

    /// Swaps two adjacent slots. Any Custom Timers overrides on either index move with their
    /// slot, so a manually-set duration stays attached to the exercise it was set for.
    private func moveRoutineItem(at index: Int, offset: Int) {
        let target = index + offset
        guard generatedRoutine.indices.contains(index), generatedRoutine.indices.contains(target) else { return }
        generatedRoutine.swapAt(index, target)
        let a = exerciseDurationOverrides.removeValue(forKey: index)
        let b = exerciseDurationOverrides.removeValue(forKey: target)
        if let b { exerciseDurationOverrides[index] = b }
        if let a { exerciseDurationOverrides[target] = a }
    }

    /// Removes a slot and shifts every override above it down by one index so overrides stay
    /// attached to the exercise they were set for rather than to a now-stale position.
    private func deleteRoutineItem(at index: Int) {
        guard generatedRoutine.indices.contains(index) else { return }
        generatedRoutine.remove(at: index)
        var reindexed: [Int: Int] = [:]
        for (key, value) in exerciseDurationOverrides {
            if key < index {
                reindexed[key] = value
            } else if key > index {
                reindexed[key - 1] = value
            }
        }
        exerciseDurationOverrides = reindexed
    }
}

/// Explains what each Intention nudges you toward during a workout — which heart-rate zone it
/// pushes you into and which focus areas it suits best — so the choice on the generator screen
/// isn't a guess.
private struct IntentionInfoView: View {
    @Environment(\.dismiss) private var dismiss
    private static let zones = ["Zone 1", "Zone 2", "Zone 3", "Zone 4", "Zone 5"]

    private func bestFor(_ intention: WorkoutIntention) -> String {
        switch intention {
        case .generalFitness:
            return "A balanced default that suits any focus area."
        case .fatBurn:
            return "Best with Cardio or full-body sessions — sustained moderate effort maximizes fat oxidation."
        case .cardioEndurance:
            return "Best with Cardio-heavy sessions and longer intervals — builds your aerobic base."
        case .strengthPower:
            return "Best with Upper/Lower/Core strength sessions and short, powerful efforts."
        case .hiit:
            return "Doesn't change which exercises are picked — pair it with the Cardio quick filter for the classic max-effort intervals."
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Each intention nudges the same routine toward a different heart-rate target and gives you a different tip per zone while you work out.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(WorkoutIntention.allCases) { intention in
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: intention.icon)
                                .foregroundStyle(intention.bannerColor)
                            Text(intention.rawValue)
                                .font(.headline)
                        }
                        Text(bestFor(intention))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ForEach(Self.zones, id: \.self) { zone in
                            HStack(alignment: .top, spacing: 8) {
                                Text(zone)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(intention.bannerColor)
                                    .frame(width: 52, alignment: .leading)
                                Text(intention.tip(for: zone))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Intentions & HR Zones")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
