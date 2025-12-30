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
                                        ExerciseRow(entry: entry)
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
            ToolbarItemGroup(placement: .topBarLeading) {
                HStack(spacing: 6) {
                    Text("Focus")
                    Picker("Focus", selection: $selectedArea) {
                        ForEach(areas, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                HStack(spacing: 6) {
                    Text("Difficulty")
                    Picker("Difficulty", selection: $selectedDifficulty) {
                        ForEach(difficulties, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }
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
    @State private var avPlayer: AVPlayer? = nil
    @State private var isPresentingPlayer = false
    @StateObject private var videoManager = VideoManager.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.exercise.name)
                    .font(.body)
                Text(entry.difficulty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if entry.exercise.videoPath != nil, VideoMode(rawValue: videoManager.videoMode) != nil {
                Button {
                    prepareAndPlay()
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if entry.exercise.videoPath != nil, VideoMode(rawValue: videoManager.videoMode) != nil {
                prepareAndPlay()
            }
        }
        .sheet(isPresented: $isPresentingPlayer) {
#if canImport(AVKit)
            if let player = avPlayer {
                VideoPlayer(player: player)
                    .onDisappear { player.pause() }
            } else {
                Text("No video available")
            }
#else
            Text("Video not supported on this platform")
#endif
        }
    }

    private func prepareAndPlay() {
        guard let rel = entry.exercise.videoPath,
              let url = videoManager.playableURL(forRelativePath: rel) else {
            return
        }
#if canImport(AVKit)
        let player = AVPlayer(url: url)
        avPlayer = player
        isPresentingPlayer = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            player.play()
        }
#endif
    }
}

