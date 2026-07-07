// ExercisesView.swift
// Shows all exercises grouped by Focus Area and Difficulty with simple filtering and video playback

import SwiftUI
#if canImport(AVKit)
import AVKit
#endif

struct CatalogEntry: Identifiable, Hashable {
    static func == (lhs: CatalogEntry, rhs: CatalogEntry) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    let id = UUID()
    let focusArea: String
    let difficulty: String
    let exercise: Exercise
}

struct ExercisesView: View {
    // We will receive the same nested dictionary used in WorkoutGeneratorView
    let exercisesByArea: [String: [String: [Exercise]]]

    @State private var selectedArea: String = "All"
    @State private var selectedDifficulty: String = "All"
    @StateObject private var videoManager = VideoManager.shared

    private static let stretchAreaNames: Set<String> = [
        "Morning Stretches", "Evening Recovery", "Cool Down", "Warm-Up: Hips", "Warm-Up: Full Body"
    ]

    private var videoModeIsEnabled: Bool {
        videoManager.videoMode != VideoMode.none.rawValue
    }

    private var allVisibleHaveNoVideos: Bool {
        let sample = filteredCatalog.prefix(10)
        guard !sample.isEmpty else { return false }
        return !sample.contains { VideoManager.shared.url(for: $0.exercise.name) != nil }
    }

    private var regularAreasInFilter: [String] {
        groupedByArea.keys.filter { !Self.stretchAreaNames.contains($0) }.sorted()
    }

    private var stretchAreasInFilter: [String] {
        groupedByArea.keys.filter { Self.stretchAreaNames.contains($0) }.sorted()
    }

    private func stretchItemsForArea(_ area: String) -> [CatalogEntry] {
        (groupedByArea[area]?.values.flatMap { $0 } ?? [])
            .sorted { $0.exercise.name < $1.exercise.name }
    }

    @State private var sheetEntry: CatalogEntry? = nil
    @State private var sheetPlayer: AVPlayer? = nil
    @State private var isPresentingVideo: Bool = false
    @State private var statusObservation: NSKeyValueObservation? = nil
    @State private var isLoadingVideo: Bool = false

    private var regularAreas: [String] {
        exercisesByArea.keys.filter { !Self.stretchAreaNames.contains($0) }.sorted()
    }

    private var stretchAreas: [String] {
        exercisesByArea.keys.filter { Self.stretchAreaNames.contains($0) }.sorted()
    }

    private var difficulties: [String] {
        let base = ["Beginner", "Medium", "Hard", "Expert/Advanced"]
        return ["All"] + base
    }

    private var flattenedCatalog: [CatalogEntry] {
        exercisesByArea.flatMap { focusArea, byDifficulty in
            byDifficulty.flatMap { difficulty, list in
                list.map { CatalogEntry(focusArea: focusArea, difficulty: difficulty, exercise: $0) }
            }
        }
    }

    private var filteredCatalog: [CatalogEntry] {
        flattenedCatalog.filter { entry in
            let matchesArea = (selectedArea == "All") || (entry.focusArea == selectedArea)
            let matchesDifficulty = (selectedDifficulty == "All") || (entry.difficulty == selectedDifficulty)
            return matchesArea && matchesDifficulty
        }
        .sorted { lhs, rhs in
            if lhs.focusArea != rhs.focusArea { return lhs.focusArea < rhs.focusArea }
            if lhs.difficulty != rhs.difficulty { return lhs.difficulty < rhs.difficulty }
            return lhs.exercise.name < rhs.exercise.name
        }
    }
    
    private func prepareAndPresent(entry: CatalogEntry) {
        // Prevent overlapping presentations
        guard !isPresentingVideo else { return }
        guard let url = VideoManager.shared.url(for: entry.exercise.name) else { return }

        // Present the sheet immediately with a loading placeholder
        isPresentingVideo = true
        isLoadingVideo = true
        sheetPlayer = nil
        sheetEntry = entry

#if canImport(AVKit)
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false

        // Use public KVO on status (retain observation in state so it lives past this function scope)
        statusObservation = item.observe(\.status, options: [.initial, .new]) { _, _ in
            if item.status == .readyToPlay {
                statusObservation?.invalidate()
                statusObservation = nil
                DispatchQueue.main.async {
                    // Start playback and then swap the player into the sheet after a short delay
                    player.play()
                    // Give the player layer a moment to produce a frame before swapping in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        sheetPlayer = player
                        isLoadingVideo = false
                    }
                }
            } else if item.status == .failed {
                statusObservation?.invalidate()
                statusObservation = nil
                DispatchQueue.main.async {
                    isPresentingVideo = false
                }
            }
        }
        _ = statusObservation
#else
        // Non-AVKit platforms: do nothing
        return
#endif
    }

    var body: some View {
        List {
            // Banner: distinguish mode-disabled vs. no recordings for this selection
            if !videoModeIsEnabled {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Video examples are disabled")
                            .font(.callout).bold()
                        Text("Switch to \"Stream\" or \"Download All\" on the main page to view video demos.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else if allVisibleHaveNoVideos {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No video recordings for this selection")
                            .font(.callout).bold()
                        Text("Video demonstrations haven't been added for these exercises yet.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Regular workout areas — alphabetical
            ForEach(regularAreasInFilter, id: \.self) { area in
                Section(header: Text(area)) {
                    let diffs: [String] = groupedByArea[area]?.keys.sorted() ?? []
                    ForEach(diffs, id: \.self) { diff in
                        let items: [CatalogEntry] = groupedByArea[area]?[diff] ?? []
                        if !items.isEmpty {
                            ForEach(items, id: \.exercise.name) { entry in
                                ExerciseRow(entry: entry) {
                                    prepareAndPresent(entry: entry)
                                }
                            }
                        }
                    }
                }
            }

            // Stretches — grouped at the bottom under one "Stretches" section
            if !stretchAreasInFilter.isEmpty {
                Section(header: HStack(spacing: 6) {
                    Image(systemName: "figure.cooldown")
                    Text("Stretches")
                }.foregroundStyle(.teal)) {
                    ForEach(stretchAreasInFilter, id: \.self) { area in
                        Text(area)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.teal)
                            .listRowBackground(Color.teal.opacity(0.06))
                        ForEach(stretchItemsForArea(area), id: \.exercise.name) { entry in
                            ExerciseRow(entry: entry) {
                                prepareAndPresent(entry: entry)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Exercises")
        .toolbar {
#if os(iOS)
            ToolbarItemGroup(placement: .topBarLeading) {
                Menu {
                    Picker("", selection: $selectedArea) {
                        Text("All").tag("All")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if !regularAreas.isEmpty {
                        Picker("Workouts", selection: $selectedArea) {
                            ForEach(regularAreas, id: \.self) { area in
                                Text(area).tag(area)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                    if !stretchAreas.isEmpty {
                        Picker("Stretches", selection: $selectedArea) {
                            ForEach(stretchAreas, id: \.self) { area in
                                Text(area).tag(area)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                } label: {
                    Label(
                        selectedArea == "All" ? "Focus" : selectedArea,
                        systemImage: selectedArea == "All" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
                    )
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Difficulty", selection: $selectedDifficulty) {
                        ForEach(difficulties, id: \.self) { diff in
                            Text(diff).tag(diff)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    Label(
                        selectedDifficulty == "All" ? "Difficulty" : selectedDifficulty,
                        systemImage: selectedDifficulty == "All" ? "dial.low" : "dial.high"
                    )
                }
            }
#else
            ToolbarItem(placement: .automatic) {
                Menu {
                    Picker("", selection: $selectedArea) {
                        Text("All").tag("All")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if !regularAreas.isEmpty {
                        Picker("Workouts", selection: $selectedArea) {
                            ForEach(regularAreas, id: \.self) { area in
                                Text(area).tag(area)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                    if !stretchAreas.isEmpty {
                        Picker("Stretches", selection: $selectedArea) {
                            ForEach(stretchAreas, id: \.self) { area in
                                Text(area).tag(area)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: selectedArea == "All"
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                        if selectedArea != "All" {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                            Text(selectedArea)
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(selectedArea == "All" ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.accentColor))
                }
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Picker("Difficulty", selection: $selectedDifficulty) {
                        ForEach(difficulties, id: \.self) { diff in
                            Text(diff).tag(diff)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: selectedDifficulty == "All" ? "dial.low" : "dial.high")
                        if selectedDifficulty != "All" {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                            Text(selectedDifficulty)
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(selectedDifficulty == "All" ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.accentColor))
                }
            }
#endif
        }
        .sheet(item: $sheetEntry, onDismiss: {
            sheetPlayer?.pause()
            sheetPlayer = nil
            isLoadingVideo = false
            isPresentingVideo = false
        }) { _ in
#if canImport(AVKit)
            ZStack(alignment: .topLeading) {
                if isLoadingVideo || sheetPlayer == nil {
                    VStack(spacing: 12) {
                        ProgressView("Loading…")
                        Text("Preparing video")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    #if os(macOS)
                    .frame(minWidth: 640, minHeight: 360)
                    #else
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #endif
                } else if let player = sheetPlayer {
                    #if os(macOS)
                    AVPlayerLayerView(player: player)
                        .frame(minWidth: 640, minHeight: 360)
                        .onDisappear { player.pause() }
                    #else
                    VideoPlayer(player: player)
                        .aspectRatio(16/9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .onDisappear { player.pause() }
                    #endif
                }
                
                // Close button in top-left corner
                Button {
                    sheetEntry = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .background(
                            Circle()
                                .fill(.black.opacity(0.5))
                                .padding(-4)
                        )
                }
                .padding(16)
                .buttonStyle(.plain)
            }
#else
            Text("Video not supported on this platform")
#endif
        }
    }

    // Build grouped structure once for List rendering
    private var groupedByArea: [String: [String: [CatalogEntry]]] {
        var result: [String: [String: [CatalogEntry]]] = [:]
        for entry in filteredCatalog {
            result[entry.focusArea, default: [:]][entry.difficulty, default: []].append(entry)
        }
        return result
    }
}

private struct ExerciseRow: View {
    let entry: CatalogEntry
    let onPlay: () -> Void

    var body: some View {
        let videoManager = VideoManager.shared
        let videoURL = videoManager.url(for: entry.exercise.name)

        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.exercise.name)
                    .font(.body)
                Text(entry.difficulty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if videoURL != nil {
                Button {
                    onPlay()
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                }
            } else if VideoMode(rawValue: videoManager.videoMode) != VideoMode.none {
                Text("No Video")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if videoURL != nil { onPlay() }
        }
    }
}

