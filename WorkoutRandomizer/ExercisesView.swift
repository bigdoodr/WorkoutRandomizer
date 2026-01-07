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

    @State private var sheetEntry: CatalogEntry? = nil
    @State private var sheetPlayer: AVPlayer? = nil
    @State private var isPresentingVideo: Bool = false
    @State private var statusObservation: NSKeyValueObservation? = nil
    @State private var isLoadingVideo: Bool = false

    private var areas: [String] {
        ["All"] + exercisesByArea.keys.sorted()
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
            // Group by Focus Area, then Difficulty
            ForEach(groupedByArea.keys.sorted(), id: \.self) { area in
                if selectedArea == "All" || selectedArea == area {
                    Section(header: Text(area)) {
                        ForEach(groupedByArea[area]!.keys.sorted(), id: \.self) { diff in
                            if selectedDifficulty == "All" || selectedDifficulty == diff {
                                let items = groupedByArea[area]![diff]!
                                if items.isEmpty {
                                    Text("No exercises")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(items) { entry in
                                        ExerciseRow(entry: entry) {
                                            prepareAndPresent(entry: entry)
                                        }
                                    }
                                }
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
                    ForEach(areas, id: \.self) { area in
                        Button(action: { selectedArea = area }) {
                            HStack {
                                Text(area)
                                if selectedArea == area { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Label("Focus", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    ForEach(difficulties, id: \.self) { diff in
                        Button(action: { selectedDifficulty = diff }) {
                            HStack {
                                Text(diff)
                                if selectedDifficulty == diff { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Label("Difficulty", systemImage: "dial.low")
                }
            }
#else
            // macOS: use automatic placement and space items apart
            ToolbarItem(placement: .automatic) {
                Menu {
                    ForEach(areas, id: \.self) { area in
                        Button(action: { selectedArea = area }) {
                            HStack {
                                Text(area)
                                if selectedArea == area { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Label("Focus", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    ForEach(difficulties, id: \.self) { diff in
                        Button(action: { selectedDifficulty = diff }) {
                            HStack {
                                Text(diff)
                                if selectedDifficulty == diff { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Label("Difficulty", systemImage: "dial.low")
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
            if isLoadingVideo || sheetPlayer == nil {
                VStack(spacing: 12) {
                    ProgressView("Loading…")
                    Text("Preparing video")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 640, minHeight: 360)
            } else if let player = sheetPlayer {
                #if os(macOS)
                AVPlayerLayerView(player: player)
                    .frame(minWidth: 640, minHeight: 360)
                    .onDisappear { player.pause() }
                #else
                VideoPlayer(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(minWidth: 640, minHeight: 360)
                    .onDisappear { player.pause() }
                #endif
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
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if videoURL != nil { onPlay() }
        }
    }
}

