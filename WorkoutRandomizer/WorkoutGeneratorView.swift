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
    /// Opens the Timer tab. Supplied by the tab container; the summary row calls it.
    var onOpenTimer: (() -> Void)? = nil
    /// Opens the Build Your Own sheet, where the My List exercises are edited.
    var onEditList: (() -> Void)? = nil

    /// Timer style, durations, rest and warm-up/cool-down — edited in the Timer tab.
    @State private var settings = GeneratorSettings.shared
    /// The exercises queued for Build Your Own — the "My List" source.
    @State private var queue = RoutineBuilderQueue.shared

    /// The focus areas that actually apply: the chips only matter for the Random source, so a
    /// stale selection can't leak into a My List workout's warm-up, name, or Health type.
    private var activeFocusAreas: Set<String> {
        settings.source == .myList ? [] : selectedFocusAreas
    }

    @State private var selectedFocusAreas: Set<String> = []
    @State private var selectedDifficulties: Set<String> = ["Beginner", "Medium", "Hard", "Expert/Advanced"]
    @State private var generatedRoutine: [Exercise] = []
    @State private var showingWorkout = false
    @State private var isGenerating = false
    @State private var scrollToGeneratedToken = UUID()

    // Feedback settings — @AppStorage, not @State, so they survive a launch. Same keys as
    // SettingsView, which is how a change made there reaches the player.
    @AppStorage("enableSound_iOS_tv_vision") private var enableSound_iOS_tv_vision = true
    @AppStorage("enableHaptics_iOS_vision") private var enableHaptics_iOS_vision = true
    @AppStorage("enableSound_macOS") private var enableSound_macOS = true
    
    @State private var selectedEquipment: Set<String> = ["None"]
    @State private var selectedIntention: WorkoutIntention = .generalFitness
    /// Last app version the user was walked through. Empty means never — which covers a fresh
    /// install *and* anyone arriving from a build that predates this tracking, so every 1.x
    /// user gets the full 2.0 tour.
    @AppStorage("lastSeenTutorialVersion") private var lastSeenTutorialVersion = ""
    /// The guide and the intention explainer share one presentation. They used to be independent
    /// `.sheet` modifiers, and on a first launch the video-mode dialog and the guide both went up
    /// in the same pass — SwiftUI presented one, silently swallowed the other, and then refused
    /// every later sheet ("only presenting a single sheet is supported").
    @State private var activeSheet: ActiveSheet? = nil
    /// The launch-time decision runs once, not on every return to this tab.
    @State private var didEvaluateGuide = false

    private enum ActiveSheet: Identifiable, Equatable {
        case guide(TutorialView.Mode)
        case intentionInfo
        /// Name-and-folder prompt for this routine. The routine travels inside the case so the
        /// sheet's content never depends on a second piece of state being set in time — reading
        /// separate state from the sheet closure showed a blank sheet on the first tap.
        case saveRoutine(SavedWorkoutRoutine)

        var id: String {
            switch self {
            case .guide(let mode): return "guide-\(mode.id)"
            case .intentionInfo: return "intentionInfo"
            case .saveRoutine: return "saveRoutine"
            }
        }

        static func == (lhs: ActiveSheet, rhs: ActiveSheet) -> Bool { lhs.id == rhs.id }
    }
    /// Where the last save landed, for the confirmation message.
    @State private var savedFolderName = ""
    @State private var confirmSaveAfterDismiss = false
    @State private var customExerciseStore = CustomExerciseStore.shared
    @State private var favorites = FavoritesStore.shared
    @State private var favoritesOnly = false
    @State private var showCustomTimers = false
    @State private var exerciseDurationOverrides: [Int: Int] = [:]
    @State private var showSaveConfirmation = false
    /// Routine indices where each ladder round begins; empty for non-ladder styles.
    @State private var ladderRoundStarts: [Int] = []

    @StateObject private var videoManager = VideoManager.shared
    @State private var catalog = ExerciseCatalog.shared
    @State private var hrZones = HRZoneSettings.shared
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
        switch settings.source {
        case .random: return !selectedFocusAreas.isEmpty && !selectedDifficulties.isEmpty
        case .myList: return !queue.items.isEmpty
        }
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

    // The timing choices live in GeneratorSettings (edited from the Timer tab). These forward to
    // it under the names this file already used, so generation logic below reads as before.
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
    private var shuffleBlockSets: Bool { settings.shuffleBlockSets }
    private var shufflePyramidOrder: Bool { settings.shufflePyramidOrder }
    private var addWarmUp: Bool { settings.addWarmUp }
    private var addCoolDown: Bool { settings.addCoolDown }
    private var effectiveRestDuration: Int { settings.effectiveRestDuration }
    private var effectiveBlocksCycleRest: Int { settings.effectiveBlocksCycleRest }
    private var warmUpSummary: String { settings.warmUpSummary }
    private var coolDownSummary: String { settings.coolDownSummary }
    private var pyramidPlan: WorkoutTiming.PyramidPlan { settings.pyramidPlan }
    private func formatBlockTime(_ seconds: Int) -> String { settings.formatBlockTime(seconds) }

    /// The one place timing rules live — built from the shared settings plus this routine's own
    /// Custom Timers overrides, so the preview, Custom Timers and the player always agree.
    var timing: WorkoutTiming { settings.timing(overrides: exerciseDurationOverrides) }

    /// The My List card: what's queued, how it will be used, and a shortcut to edit it.
    @ViewBuilder
    private var myListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("My List")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Edit List") { onEditList?() }
                    .font(.subheadline)
            }

            if queue.items.isEmpty {
                Text("Nothing here yet. Swipe exercises in the Exercises tab to add them, or tap Edit List.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let names = queue.items.map(\.name)
                Text("\(names.count) exercise\(names.count == 1 ? "" : "s"): \(names.prefix(3).joined(separator: ", "))\(names.count > 3 ? "…" : "")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Picker("How to use the list", selection: $settings.listMode) {
                ForEach(ListMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(!settings.performAllAvailable)

            if !settings.performAllAvailable {
                Text("Pyramid sets how many exercises it needs from the Total Duration, so your list is used as a pool to draw from.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if settings.listMode == .performAll {
                Text(performAllCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Shuffle order", isOn: $settings.shuffleListOrder)
                    .font(.subheadline)
            } else {
                Text("Fills the chosen length by drawing from your list, repeating exercises if needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .id("myListSection")
    }

    private var performAllCaption: String {
        switch timerStyle {
        case .blocks:
            return "Uses your list in order for each cycle: \(blocksCount * exercisesPerBlock) exercise slots per cycle, cycling back to the start if the list is shorter."
        case .addOn, .addOnTakeAway:
            return "Builds the ladder from your list in order, up to 10 exercises."
        default:
            return "Does every exercise in your list once, in order. The total length follows the list."
        }
    }

    /// One line describing the timer that will be applied, shown on the summary row.
    private var timerSummary: String {
        var parts = [timerStyle.shortLabel]
        switch timerStyle {
        case .blocks:
            parts.append("\(blocksCount) blocks × \(exercisesPerBlock)")
            parts.append("\(blocksTotalSets) cycle\(blocksTotalSets == 1 ? "" : "s")")
            parts.append(formatBlockTime(settings.blocksTotalSeconds))
        case .pyramid:
            parts.append("\(totalDuration) min")
        case .standard:
            parts.append("\(totalDuration) min")
            if shuffleExerciseTime {
                parts.append("shuffled work, rest ½ of each")
            } else {
                parts.append("\(exerciseDuration)s work / \(effectiveRestDuration)s rest")
            }
        case .addOn, .addOnTakeAway:
            parts.append("\(totalDuration) min")
            parts.append("\(exerciseDuration)s work / \(effectiveRestDuration)s rest")
        }
        if addWarmUp { parts.append("warm-up") }
        if addCoolDown { parts.append("cool-down") }
        return parts.joined(separator: " · ")
    }
    
    var body: some View {
        // The enclosing NavigationStack (and the title) live in GenerateHubView, which switches
        // between this and the stretch generator.
        Group {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {


                        // Source — Random draws from the focus areas below; My List uses the exercises
                        // queued in Build Your Own, with the timer style applied to them.
                        Picker("Source", selection: $settings.source) {
                            ForEach(GenerationSource.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        if settings.source == .myList {
                            myListSection
                        }

                        if settings.source == .random {
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

                        // Timer summary — style and lengths are set in the Timer tab; this is just a
                        // reminder of what will be applied, and a shortcut there.
                        Button { onOpenTimer?() } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Timer")
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                    Text(timerSummary)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)



                        // Generate Button
                        Button {
                            if settings.source == .myList && queue.items.isEmpty {
                                withAnimation { proxy.scrollTo("myListSection", anchor: .top) }
                            } else if settings.source == .random && selectedFocusAreas.isEmpty {
                                withAnimation { proxy.scrollTo("focusAreasSection", anchor: .top) }
                            } else if settings.source == .random && selectedDifficulties.isEmpty {
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
                                } else if settings.source == .myList && queue.items.isEmpty {
                                    Text("Add exercises to My List first")
                                } else if settings.source == .random && selectedFocusAreas.isEmpty {
                                    Text("Focus Area(s) must be selected")
                                } else if settings.source == .random && selectedDifficulties.isEmpty {
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

                                    // Export and Import live in the Saved tab now: save a routine
                                    // here, then export it from there.
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
                            .id(scrollToGeneratedToken)
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingWorkout) {
            WorkoutPlayerView(
                routine: generatedRoutine,
                // The same value the Custom Timers editor reads, so the preview and the clock
                // are guaranteed to agree.
                timing: timing,
                intention: selectedIntention,
                selectedFocusAreas: activeFocusAreas,
                enableSound_iOS_tv_vision: enableSound_iOS_tv_vision,
                enableHaptics_iOS_vision: enableHaptics_iOS_vision,
                enableSound_macOS: enableSound_macOS,
                ladderRoundStarts: ladderRoundStarts.isEmpty ? nil : ladderRoundStarts
            )
            // A stray scroll/swipe shouldn't be able to abruptly end an active routine —
            // stopping now requires the confirmed Stop button inside the player.
            .interactiveDismissDisabled(true)
        }
        // One sheet for the guide and the intention explainer, so the two can never both try to
        // present. The video-mode prompt waits until neither is on screen.
        .sheet(item: $activeSheet, onDismiss: {
            if confirmSaveAfterDismiss {
                // Presenting the alert while the sheet is still leaving can drop it.
                confirmSaveAfterDismiss = false
                showSaveConfirmation = true
            } else {
                promptForVideoModeIfNeeded()
            }
        }) { sheet in
            switch sheet {
            case .guide(let mode):
                TutorialView(mode: mode)
            case .intentionInfo:
                IntentionInfoView()
            case .saveRoutine(let routine):
                SaveRoutinePromptView(title: "Save as Routine", initialName: routine.name) { name, category in
                    SavedRoutineStore.shared.save(routine.filed(name: name, category: category))
                    savedFolderName = category ?? RoutineFolders.uncategorizedName
                    confirmSaveAfterDismiss = true
                }
            }
        }
        .alert("Routine Saved", isPresented: $showSaveConfirmation) {
            Button("OK") { }
        } message: {
            Text("Saved to \"\(savedFolderName)\" in the Saved tab.")
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
        .task {
            await hrZones.refreshFromHealthKit()
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
            // Random draws from the focus areas and filters; My List uses the queue instead.
            let usingList = settings.source == .myList
            let performAll = settings.usesPerformAll
            let listed = usingList ? myListExercises() : []
            let pool: [Exercise] = usingList ? uniqueByName(listed) : randomPool()

            guard !pool.isEmpty else {
                isGenerating = false
                return
            }

            // Ladder styles build their own round structure from distinct rungs, so they skip
            // the flat maxExercises/createBalancedRoutine path entirely.
            if timerStyle.isLadder {
                let takeAway = timerStyle == .addOnTakeAway
                // A ladder beyond ~10 rungs is impractical to remember, let alone perform.
                let units = performAll
                    ? orderedLadderUnits(from: listed, maxUnits: 10)
                    : ladderUnits(from: pool, maxUnits: 10)
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
                // When shuffling, no single exercise duration describes the routine, so the
                // slot count is sized off the average of the same presets the shuffle draws
                // from — otherwise the routine was sized for a fixed, unshuffled length and
                // ran short or long of the selected Total Duration once shuffle picked bigger
                // or smaller values.
                let workSeconds: Double
                let restSeconds: Double
                if shuffleExerciseTime {
                    let options = Self.shuffleExerciseDurationOptions
                    workSeconds = Double(options.reduce(0, +)) / Double(options.count)
                    restSeconds = restLinkedToWork
                        ? Double(options.map { WorkoutTiming.restSeconds(forWork: $0) }.reduce(0, +)) / Double(options.count)
                        : Double(effectiveRestDuration)
                } else {
                    workSeconds = Double(exerciseDuration)
                    restSeconds = Double(effectiveRestDuration)
                }
                let fullCycle = workSeconds + (restSeconds / Double(restEvery))
                let totalSecs = Double(totalDuration) * 60
                maxExercises = Int(ceil(totalSecs / fullCycle))
            case .addOn, .addOnTakeAway:
                maxExercises = 0   // unreachable: ladder styles return before this point
            }

            // Create balanced routine
            // Perform all uses the list as written; everything else (Random, or Draw from) picks
            // from the pool. Blocks needs exactly one set's worth of slots, so it takes the first
            // `maxExercises` in order and cycles the list if it is shorter.
            let selected: [Exercise]
            if performAll {
                selected = timerStyle == .standard
                    ? orderedUnits(listed).flatMap { $0 }
                    : GeneratorSettings.fitUnits(orderedUnits(listed), toSlots: maxExercises)
            } else {
                selected = createBalancedRoutine(from: pool, maxCount: maxExercises)
            }

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

    // MARK: - My List source

    /// The My List queue as Exercise values, in order, duplicates kept. Catalog exercises keep
    /// their video, equipment and single-sided info; a My Exercises entry has no catalog record,
    /// so it becomes a basic exercise, the same way the random pool treats custom exercises.
    private func myListExercises() -> [Exercise] {
        var byName: [String: Exercise] = [:]
        for (_, byDifficulty) in exercises {
            for (_, list) in byDifficulty {
                for exercise in list where byName[exercise.name] == nil {
                    byName[exercise.name] = exercise
                }
            }
        }
        return queue.items.map { item in
            byName[item.name] ?? Exercise(name: item.name, videoPath: nil, equipment: ["None"])
        }
    }

    private func uniqueByName(_ list: [Exercise]) -> [Exercise] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.name).inserted }
    }

    /// The list as shuffle-safe units (a single-sided exercise's Left/Right pair stays together),
    /// in list order — or shuffled, when Shuffle order is on.
    private func orderedUnits(_ list: [Exercise]) -> [[Exercise]] {
        let units = list.map { expandSides($0) }
        return settings.shuffleListOrder ? units.shuffled() : units
    }

    /// Add-On ladders from the list: each rung is one listed exercise (deduplicated), in order.
    private func orderedLadderUnits(from list: [Exercise], maxUnits: Int) -> [[Exercise]] {
        var seen = Set<String>()
        let distinct = list.filter { seen.insert($0.name).inserted }
        return Array(orderedUnits(distinct).prefix(maxUnits))
    }



    /// The Random source: exercises from the selected focus areas, difficulties and equipment,
    /// plus matching custom exercises, optionally limited to favorites.
    private func randomPool() -> [Exercise] {
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
        return pool
    }

    /// Gives each Standard-style work slot its own randomly-picked duration from the same
    /// presets as the Exercise Duration chips, via the same override mechanism Custom Timers
    /// uses — so this is just an automated version of hand-editing every slot. When rest is
    /// Linked, each rest slot is re-derived from the shuffled work value that precedes it
    /// (rather than the global Exercise Duration) so it still shows as half that slot's work;
    /// a Manual rest keeps the hand-picked value untouched. Runs after `publish(routine:)` so
    /// it can key off `generatedRoutine`'s final indices rather than re-deriving the warm-up
    /// offset itself.
    private func applyShuffledExerciseTimes() {
        let options = Self.shuffleExerciseDurationOptions
        for (index, exercise) in generatedRoutine.enumerated() {
            if exercise.name == "Rest" {
                if restLinkedToWork, index > 0, let precedingWork = exerciseDurationOverrides[index - 1] {
                    exerciseDurationOverrides[index] = WorkoutTiming.restSeconds(forWork: precedingWork)
                }
                continue
            }
            guard !exercise.isPreparation else { continue }
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
    private static var warmUpSecondsPerMove: Int { GeneratorSettings.warmUpSecondsPerMove }
    private static var coolDownSecondsPerHold: Int { GeneratorSettings.coolDownSecondsPerHold }
    private static var coolDownHoldCount: Int { GeneratorSettings.coolDownHoldCount }
    private static var shuffleExerciseDurationOptions: [Int] { GeneratorSettings.shuffleExerciseDurationOptions }

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
                || !Set(exercise.relatedFocusAreas).isDisjoint(with: activeFocusAreas)
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
        // Sub-areas ("Core: Strength") are named for their parent so the title doesn't read
        // "Core & Core: Strength Workout".
        var seenAreas = Set<String>()
        let focusLabel = activeFocusAreas.sorted()
            .map { $0.components(separatedBy: ":").first ?? $0 }
            .filter { seenAreas.insert($0).inserted }
            .prefix(2)
            .joined(separator: " & ")
        let routineName = focusLabel.isEmpty
            ? (settings.source == .myList ? "My List Workout" : "My Workout")
            : "\(focusLabel) Workout"
        let routine = SavedWorkoutRoutine(
            name: routineName,
            routineDescription: "",
            source: "My Routines",
            sourceURL: "",
            exercises: savedExercises,
            accentColorName: "purple",
            systemImage: "dumbbell.fill",
            // Remembered so replaying from Saved is logged the way the live run would be
            // (a Core-only workout stays Core Training instead of being guessed again).
            kind: SavedRoutineKind.forFocusAreas(activeFocusAreas)
        )
        activeSheet = .saveRoutine(routine)
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
