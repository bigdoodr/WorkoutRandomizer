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
    
    // Video paths are now derived from the ExerciseCatalog (loaded from remote JSON / bundled fallback).
    // No need to maintain a separate hardcoded dictionary.
    @MainActor
    var videoPaths: [String: String] {
        ExerciseCatalog.shared.videoPaths
    }

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

