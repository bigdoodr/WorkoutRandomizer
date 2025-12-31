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
    private struct IdentifiedPlayer: Identifiable {
        let id = UUID()
        let player: AVPlayer
    }

    let entry: CatalogEntry
    @State private var avPlayer: AVPlayer? = nil
    @State private var presentedPlayerItem: IdentifiedPlayer? = nil

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
            if let url = videoURL {
                Button {
                    guard presentedPlayerItem == nil else { return }
                    if let player = makePlayer(for: url) {
                        avPlayer = player
                        let identified = IdentifiedPlayer(player: player)
                        presentedPlayerItem = identified
                    }
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard presentedPlayerItem == nil else { return }
            if let url = videoURL, let player = makePlayer(for: url) {
                avPlayer = player
                let identified = IdentifiedPlayer(player: player)
                presentedPlayerItem = identified
            }
        }
        .sheet(item: $presentedPlayerItem, onDismiss: {
            avPlayer?.pause()
            avPlayer = nil
        }) { identified in
#if canImport(AVKit)
            VideoPlayer(player: identified.player)
                .aspectRatio(16/9, contentMode: .fit)
                .frame(minWidth: 640, minHeight: 360)
                .onAppear { identified.player.play() }
                .onDisappear {
                    identified.player.pause()
                }
                #if os(macOS)
                .presentationSizing(.fitted)
                #endif
#else
            Text("Video not supported on this platform")
#endif
        }
    }

    private func makePlayer(for url: URL) -> AVPlayer? {
#if canImport(AVKit)
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        return player
#else
        return nil
#endif
    }
}

