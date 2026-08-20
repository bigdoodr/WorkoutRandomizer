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
    @State private var restDuration = 10
    @State private var restEvery = 1
    @State private var generatedRoutine: [Exercise] = []
    @State private var showingWorkout = false
    @State private var isGenerating = false
    @State private var scrollToGeneratedToken = UUID()
    @State private var showingImportExport = false
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var exportDocument: WorkoutDocument?
    
    // Feedback settings
    @State private var enableSound_iOS_tv_vision = true
    @State private var enableHaptics_iOS_vision = true
    @State private var enableSound_macOS = true
    
    @State private var selectedEquipment: Set<String> = ["None"]
    @State private var timerStyle: TimerStyle = .standard
    @State private var selectedIntention: WorkoutIntention = .generalFitness
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
    @AppStorage("useAdvancedView") private var useAdvancedView = false
    @State private var showingTutorial = false
    @State private var customExerciseStore = CustomExerciseStore.shared
    @State private var showCustomTimers = false
    @State private var exerciseDurationOverrides: [Int: Int] = [:]
    @State private var showSaveConfirmation = false

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

#if os(macOS)
    private var platformBackgroundColor: NSColor { .windowBackgroundColor }
#else
    private var platformBackgroundColor: UIColor { .systemBackground }
#endif

    @ViewBuilder
    private var focusAreaFilterRow: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickFilters, id: \.label) { filter in
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
                .padding(.vertical, 2)
                .padding(.trailing, 24)
            }
            LinearGradient(
                colors: [.clear, Color(platformBackgroundColor)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 36)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var difficultyFilterRow: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(difficulties, id: \.self) { level in
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
                .padding(.vertical, 2)
                .padding(.trailing, 24)
            }
            LinearGradient(
                colors: [.clear, Color(platformBackgroundColor)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 36)
            .allowsHitTesting(false)
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

    var blocksSuperSetSeconds: Int {
        blockDurations.reduce(0) { $0 + exercisesPerBlock * $1 * 2 }
    }
    var blocksAvailableTotalSets: [Int] {
        let superSetSec = blocksSuperSetSeconds
        guard superSetSec > 0 else { return [1] }
        var options: [Int] = []
        var n = 1
        while n * superSetSec <= 90 * 60 { options.append(n); n += 1 }
        return options.isEmpty ? [1] : options
    }
    var blocksTotalSeconds: Int { blocksTotalSets * blocksSuperSetSeconds }

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
            restDuration: restDuration,
            blocksConfig: timerStyle == .blocks
                ? RepeatingBlocksConfig(exercisesPerBlock: exercisesPerBlock, blockDurations: blockDurations)
                : nil,
            overrides: exerciseDurationOverrides
        )
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
                        
                        // View Exercises / My Exercises
                        HStack(spacing: 10) {
                            NavigationLink(destination: ExercisesView(exercisesByArea: exercises)) {
                                HStack {
                                    Image(systemName: "list.bullet.rectangle.portrait")
                                    Text("All Exercises")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.purple)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            NavigationLink(destination: MyExercisesView(
                                focusAreas: focusAreas,
                                difficulties: difficulties
                            )) {
                                HStack {
                                    Image(systemName: "person.badge.plus")
                                    Text("My Exercises")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.indigo)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }

                        HStack(spacing: 10) {
                            NavigationLink(destination: StretchRoutineView()) {
                                HStack {
                                    Image(systemName: "figure.cooldown")
                                    Text("Stretch Routine")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.teal)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            NavigationLink(destination: SavedRoutinesView()) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                    Text("Saved Routines")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.brown)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        
                        // Basic/Advanced mode label
                        if !useAdvancedView {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Tap \(Image(systemName: "slider.horizontal.3")) for advanced options")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

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

                        // Intention — single-select icon chips
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Intention")
                                .font(.title2)
                                .fontWeight(.semibold)

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

                            HStack(spacing: 15) {
                                ForEach(useAdvancedView ? TimerStyle.allCases : [TimerStyle.standard]) { style in
                                    HStack {
                                        Image(systemName: timerStyle == style ? "circle.fill" : "circle")
                                            .foregroundStyle(timerStyle == style ? .blue : .secondary)
                                        Text(style.rawValue)
                                            .font(.subheadline)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture { timerStyle = style }
                                }
                            }

                            if timerStyle == .pyramid && useAdvancedView {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Pyramid cycle repeats to fill total duration — each round shares work & rest:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    ForEach(["30s work + 30s rest", "40s work + 40s rest", "50s work + 50s rest",
                                             "50s work + 50s rest", "40s work + 40s rest", "30s work + 30s rest"], id: \.self) { label in
                                        Text("• \(label)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(10)
                                .background(.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }

                        // Durations — preset chips
                        if timerStyle == .standard || timerStyle == .pyramid {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Durations")
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                VStack(alignment: .leading, spacing: 14) {
                                    // Total Duration presets
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Total Duration")
                                            .font(.subheadline)
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                ForEach([5, 10, 20, 30, 45, 60, 90], id: \.self) { preset in
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
                                            .padding(.horizontal, 2)
                                        }
                                    }

                                    if timerStyle == .standard {
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

                                        // Rest Duration presets
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Rest Duration")
                                                .font(.subheadline)
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

                                        // Rest Frequency — exercises per circuit before rest
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

                        // Advanced only: Repeating Blocks config, Feedback, Video Options
                        if useAdvancedView {

                        // Repeating Blocks Configuration
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
                                        Text("Work Duration per Block (rest = same)")
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
                                                Text("\(n)× cycle · \(formatBlockTime(n * blocksSuperSetSeconds))")
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
                                    }
                                }
                            }
                        }

                        // Feedback Settings
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Feedback")
                                .font(.title2)
                                .fontWeight(.semibold)

                            VStack(spacing: 10) {
#if os(iOS) || os(tvOS) || os(visionOS)
                                Toggle(isOn: $enableSound_iOS_tv_vision) {
                                    Label("Sounds (iOS/tvOS/visionOS)", systemImage: enableSound_iOS_tv_vision ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                }
#endif
#if os(iOS)
                                Toggle(isOn: $enableHaptics_iOS_vision) {
                                    Label("Haptics (iOS)", systemImage: enableHaptics_iOS_vision ? "hand.tap.fill" : "hand.raised")
                                }
#endif
#if os(macOS)
                                Toggle(isOn: $enableSound_macOS) {
                                    Label("Sounds (macOS)", systemImage: enableSound_macOS ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                }
#endif
                            }
                        }
                        
                        // Video Options
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Video Options")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Picker("Video Mode", selection: $videoModeRaw) {
                                ForEach(VideoMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: videoModeRaw) { _, newValue in
                                videoManager.videoMode = newValue
                            }
                            
                            if VideoMode(rawValue: videoModeRaw) == .downloadOnFirstLaunch {
                                if let progress = downloadProgress {
                                    Text("Downloading videos \(progress.completed) of \(progress.total)...")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button("Download Videos") {
                                        startVideoDownload()
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                        
                        } // end if useAdvancedView

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
                                    if useAdvancedView {
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
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { useAdvancedView.toggle() }
                    } label: {
                        Label(useAdvancedView ? "Basic" : "Advanced",
                              systemImage: useAdvancedView ? "slider.horizontal.below.square.and.square.filled" : "slider.horizontal.3")
                            .labelStyle(.iconOnly)
                    }
                }
#else
                ToolbarItem {
                    Button { withAnimation { useAdvancedView.toggle() } } label: {
                        Label(useAdvancedView ? "Basic" : "Advanced",
                              systemImage: useAdvancedView ? "slider.horizontal.below.square.and.square.filled" : "slider.horizontal.3")
                    }
                }
#endif
            }
        }
        .onChange(of: useAdvancedView) { _, newValue in
            if !newValue && timerStyle != .standard {
                timerStyle = .standard
            }
        }
        .sheet(isPresented: $showingWorkout) {
            WorkoutPlayerView(
                routine: generatedRoutine,
                exerciseDuration: exerciseDuration,
                restDuration: restDuration,
                restEvery: restEvery,
                timerStyle: timerStyle,
                intention: selectedIntention,
                selectedFocusAreas: selectedFocusAreas,
                blocksConfig: timerStyle == .blocks ? RepeatingBlocksConfig(exercisesPerBlock: exercisesPerBlock, blockDurations: blockDurations) : nil,
                enableSound_iOS_tv_vision: enableSound_iOS_tv_vision,
                enableHaptics_iOS_vision: enableHaptics_iOS_vision,
                enableSound_macOS: enableSound_macOS,
                durationOverrides: exerciseDurationOverrides.isEmpty ? nil : exerciseDurationOverrides
            )
            // A stray scroll/swipe shouldn't be able to abruptly end an active routine —
            // stopping now requires the confirmed Stop button inside the player.
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $showingTutorial) {
            TutorialView()
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
            if !videoManager.didPromptForVideoMode {
                showVideoModePrompt = true
            }
            if !hasSeenTutorial {
                showingTutorial = true
            }
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
    
    private func startVideoDownload() {
        // Gather keys for all exercises that have known videos in VideoManager
        let allKeys = exercises.values
            .flatMap { $0.values.flatMap { $0 } }
            .map { $0.name }
            .filter { VideoManager.shared.path(for: $0) != nil }
            .unique()

        downloadProgress = (completed: 0, total: allKeys.count)

        videoManager.downloadAll(keys: allKeys, progress: { completed, total in
            downloadProgress = (completed: completed, total: total)
        }, completion: {
            downloadProgress = nil
        })
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

            guard !pool.isEmpty else {
                isGenerating = false
                return
            }

            // Compute target exercise count based on timer style
            let pyramidCycleSecs = WorkoutTiming.pyramidIntervals.reduce(0) { $0 + $1.work + $1.rest }
            let maxExercises: Int
            switch timerStyle {
            case .pyramid:
                let cycles = max(1, Int(ceil(Double(totalDuration) * 60.0 / Double(pyramidCycleSecs))))
                maxExercises = cycles * WorkoutTiming.pyramidIntervals.count
            case .blocks:
                maxExercises = blocksTotalSets * blocksCount * exercisesPerBlock
            case .standard:
                let fullCycle = Double(exerciseDuration) + (Double(restDuration) / Double(restEvery))
                let totalSecs = Double(totalDuration) * 60
                maxExercises = Int(ceil(totalSecs / fullCycle))
            }

            // Create balanced routine
            let selected = createBalancedRoutine(from: pool, maxCount: maxExercises)

            // Build final routine with rests
            var routine: [Exercise] = []
            if timerStyle == .pyramid || timerStyle == .blocks {
                // For blocks with shuffle: divide exercises into sets and shuffle each independently
                let exercises: [Exercise]
                if timerStyle == .blocks && shuffleBlockSets && blocksTotalSets > 1 {
                    let setSize = blocksCount * exercisesPerBlock
                    var basePool = Array(selected.prefix(setSize))
                    // Don't split a Left/Right pair across the set boundary — pull the
                    // matching Right in so shuffling never separates the two sides.
                    if let last = basePool.last, last.name.hasSuffix(" (Left)"),
                       basePool.count < selected.count,
                       selected[basePool.count].name == last.name.replacingOccurrences(of: " (Left)", with: " (Right)") {
                        basePool.append(selected[basePool.count])
                    }
                    // Shuffle Left/Right pairs as a single atomic unit so the two sides
                    // always stay back-to-back after shuffling.
                    let baseUnits = atomicSideUnits(basePool)
                    var shuffled: [Exercise] = []
                    for _ in 0..<blocksTotalSets {
                        shuffled.append(contentsOf: baseUnits.shuffled().flatMap { $0 })
                    }
                    exercises = shuffled
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

            generatedRoutine = routine
            exerciseDurationOverrides.removeAll()
            showCustomTimers = false
            isGenerating = false
            scrollToGeneratedToken = UUID()
        }
    }
    
    // Single-sided exercises are chosen as one slot but always expand into their
    // Left/Right pair together, so the two sides land back-to-back in the routine
    // (only a rest, never another exercise, can end up between them).
    private func expandSides(_ exercise: Exercise) -> [Exercise] {
        guard exercise.singleSided else { return [exercise] }
        let left  = Exercise(name: "\(exercise.name) (Left)",  videoPath: exercise.videoPath, equipment: exercise.equipment, isMovement: exercise.isMovement)
        let right = Exercise(name: "\(exercise.name) (Right)", videoPath: exercise.videoPath, equipment: exercise.equipment, isMovement: exercise.isMovement)
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
        let exportableExercises = generatedRoutine.map { exercise in
            ExportableExercise(
                name: exercise.name,
                isTimeBased: true,
                exerciseDuration: exercise.name == "Rest" ? restDuration : exerciseDuration,
                restDuration: exercise.name == "Rest" ? 0 : restDuration,
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
                let restDur = exerciseDurationOverrides[i] ?? restDuration
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
                let dur = exerciseDurationOverrides[i] ?? exerciseDuration
                savedExercises.append(SavedRoutineExercise(
                    name: ex.name,
                    duration: dur,
                    restDuration: 0,
                    singleSided: ex.singleSided,
                    moveType: .move
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
                    restDuration = exportableExercise.restDuration
                }
                didSetDurations = true
            }
        }
        
        generatedRoutine = importedRoutine
        scrollToGeneratedToken = UUID()
    }
}
