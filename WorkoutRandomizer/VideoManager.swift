// VideoManager.swift
// Handles video mode, resolving URLs, and optional bulk download

import Foundation
import SwiftUI
import Combine
internal import UniformTypeIdentifiers

enum VideoMode: String, CaseIterable, Identifiable {
    case downloadOnFirstLaunch = "Download All"
    case stream = "Stream"
    case none = "No Video"
    
    var id: String { rawValue }
}

final class VideoManager: ObservableObject {
    @MainActor static let shared = VideoManager()
    private init() {}
    
    // Canonical mapping of exercise identifiers to relative video paths
    // Key examples could be exercise names or IDs used in ExercisesView/WorkoutRandomizer
    // Update/add keys to match your app's data.
    // Relative paths should be rooted at the site root (e.g., "/resources/squats.mp4").
    @MainActor
    let videoPaths: [String: String] = [
        // Chest
        "Push-Ups": "/resources/pushupsAngle2.mp4",
        "One-Legged Skier Push-Ups": "/resources/onelegskierpushups.mp4",
        // Legs
        "Squats": "/resources/squats.mp4",
        "3-Way Lunges": "/resources/3wayLungesAngle2.mp4",
        "Alternating Split Squats": "/resources/splitSquats.mp4",
        "Frog Hops": "/resources/frogHops.mp4",
        "Squat Jumps": "/resources/squatJumps.mp4",
        "180° Squat Jumps": "/resources/180JumpSquats.mp4",
        "Ninja Tuck Jumps": "/resources/ninjaTuckJumps.mp4",
        "Prisoner Squat Jumps": "/resources/prisonerSquatJumps.mp4",
        "3-Point Alternating Hops": "/resources/3pointAltHops.mp4",
        "Prisoner Ninja Tuck Jumps": "/resources/prisonerNinjaTuckJumps.mp4",
        "Triple Skyfalls": "/resources/3xskyfalls.mp4",
        // Legs, No Cardio
        "Reverse Lunge to High Knee": "/resources/reverseLungeHighKneeAngle2.mp4",
        // Shoulders
        "Pike Push-Ups": "/resources/pikePushups.mp4",
        "Kneeling Spider-Man Push-Ups": "/resources/kneelingSpidermanPushups.mp4",
        "Spider-Man Push-Ups": "/resources/spidermanPushups.mp4",
        // Triceps
        "Bench Dips": "/resources/benchDipsAngle1.mp4",
        // Glutes
        "Bridges": "/resources/bridgesAngle2.mp4",
        "Hip Bucks": "/resources/hipBucks.mp4",
        "Single Leg Hip Bucks": "/resources/singleLegHipBucks.mp4",
        // Core
        "Bear Taps": "/resources/bearTapsAngle2.mp4",
        "Walking Marches": "/resources/walkingMarches.mp4",
        "Jackknives - Level 1": "/resources/jackknivesLevel1.mp4",
        "Russian V-Twists": "/resources/russianVTwistsAngle1.mp4",
        "Spider-Man Lunges": "/resources/spidermanLungesAngle2.mp4",
        "Bicycle Crunches": "/resources/bicycleCrunchesAngle2.mp4",
        "Jackknives - Level 2": "/resources/jackknivesLevel2.mp4",
        "Mountain Climbers": "/resources/mountainClimbers.mp4",
        "Plank Elbow to Knee Taps": "/resources/plankElbowToKneeTaps.mp4",
        "Side Kickthroughs": "/resources/sideKickthroughs.mp4",
        "Twisting Piston Push-Ups": "/resources/twistingPistonPushUps.mp4",
        // Core, No Cardio
        "Ab-Roller": "/resources/abRollerAngle1.mp4",
        "Bird Dogs": "/resources/birdDogs.mp4",
        "Good Mornings": "/resources/goodMorningsAngle2.mp4",
        "Swipers": "/resources/swipersAngle2.mp4",
        "Plank Elbow Ups": "/resources/plankElbowUps.mp4",
        "Shoulder Taps": "/resources/shoulderTapsAngle1.mp4",
        // Cardio
        "Jump/Air Rope": "/resources/jumprope.mp4",
        "Shadow Boxing": "/resources/shadowboxing.mp4",
        "Toe Taps": "/resources/toeTaps.mp4",
        "High Knees": "/resources/highknees.mp4",
        "Jumping Jacks": "/resources/jumpingjacks.mp4",
        "Skier Hops": "/resources/skierhops.mp4",
    ]

    // Resolve a relative path for a given key (exercise name/ID)
    @MainActor
    func path(for key: String) -> String? {
        videoPaths[key]
    }

    // Resolve a playable URL for a given key using the current videoMode
    @MainActor
    func url(for key: String) -> URL? {
        guard let rel = path(for: key) else {
            print("VideoManager.url(for:): No path for key:", key)
            return nil
        }
        let result = playableURL(forRelativePath: rel)
        print("VideoManager.url(for: \(key)) ->", result?.absoluteString ?? "nil", "mode=", videoMode)
        return result
    }

    // Convenience for bulk download by keys
    @MainActor
    func downloadAll(keys: [String], progress: @escaping (Int, Int) -> Void, completion: @escaping () -> Void) {
        // Only kick off downloads when the mode is Download All
        guard videoMode == VideoMode.downloadOnFirstLaunch.rawValue else {
            print("VideoManager.downloadAll(keys:): Skipping bulk download because mode is", videoMode)
            completion()
            return
        }
        let paths = keys.compactMap { videoPaths[$0] }
        print("VideoManager.downloadAll(keys:): Starting bulk download for", paths.count, "items")
        downloadAll(relativePaths: paths, progress: progress, completion: completion)
    }
    
    @MainActor @AppStorage("videoMode") var videoMode: String = VideoMode.stream.rawValue
    @MainActor @AppStorage("didPromptForVideoMode") var didPromptForVideoMode: Bool = false
    
    private var activeDownloadTasks = [URLSessionDownloadTask]()
    
    // Cache directory for videos
    private var cacheDirectory: URL {
        let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        return urls[0].appendingPathComponent("WorkoutVideos", conformingTo: .directory)
    }
    
    // Build a canonical remote URL from a relative path like "/resources/squats.mp4"
    func remoteURL(forRelativePath rel: String) -> URL? {
        var path = rel
        if path.hasPrefix("/") { path.removeFirst() }
        let s = "https://bigdoodr.github.io/\(path)"
        print("VideoManager.remoteURL:", s)
        return URL(string: s)
    }
    
    // Local URL in cache by filename
    func localURL(forRelativePath rel: String) -> URL {
        let fileName = (rel as NSString).lastPathComponent
        return cacheDirectory.appendingPathComponent(fileName)
    }
    
    func ensureCacheDirectory() {
        let dir = cacheDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
    
    @MainActor func playableURL(forRelativePath rel: String?) -> URL? {
        guard let rel = rel else { return nil }
        switch VideoMode(rawValue: videoMode) ?? .stream {
        case .none:
            return nil
        case .stream:
            return remoteURL(forRelativePath: rel)
        case .downloadOnFirstLaunch:
            let local = localURL(forRelativePath: rel)
            if FileManager.default.fileExists(atPath: local.path) {
                return local
            } else {
                return remoteURL(forRelativePath: rel) // fallback to stream if not yet downloaded
            }
        }
    }
    
    @MainActor func downloadAll(relativePaths: [String], progress: @escaping (Int, Int) -> Void, completion: @escaping () -> Void) {
        activeDownloadTasks.removeAll()
        ensureCacheDirectory()
        let unique = Array(Set(relativePaths))
        guard !unique.isEmpty else { completion(); return }
        let total = unique.count
        var completed = 0

        for rel in unique {
            self.downloadIfNeeded(relativePath: rel) {
                completed += 1
                progress(completed, total)
                if completed == total { completion() }
            }
        }
    }
    
    @MainActor func cancelAllDownloads() {
        for task in activeDownloadTasks {
            task.cancel()
        }
        activeDownloadTasks.removeAll()
    }
    
    private func downloadIfNeeded(relativePath: String, completion: @escaping () -> Void) {
        let dest = localURL(forRelativePath: relativePath)
        if FileManager.default.fileExists(atPath: dest.path) {
            print("Download skipped (exists):", dest.lastPathComponent)
            completion(); return
        }
        guard let remote = remoteURL(forRelativePath: relativePath) else {
            print("Download skipped (bad URL) for:", relativePath)
            completion(); return
        }
        let tmp = dest.appendingPathExtension("download")
        print("Starting download:", remote.absoluteString)
        let task = URLSession.shared.downloadTask(with: remote) { url, _, _ in
            defer { completion() }
            guard let url else { return }
            do {
                self.ensureCacheDirectory()
                if FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.removeItem(at: dest)
                }
                if FileManager.default.fileExists(atPath: tmp.path) {
                    try? FileManager.default.removeItem(at: tmp)
                }
                try FileManager.default.moveItem(at: url, to: tmp)
                try FileManager.default.moveItem(at: tmp, to: dest)
            } catch {
                // ignore errors for now
            }
        }
        DispatchQueue.main.async {
            self.activeDownloadTasks.append(task)
        }
        task.resume()
    }
}

