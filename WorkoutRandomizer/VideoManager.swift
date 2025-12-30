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
        return URL(string: "https://bigdoodr.github.io/\(path)")
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
        let queue = DispatchQueue(label: "VideoDownloadQueue")
        for rel in unique {
            queue.async {
                Task { @MainActor in
                    self.downloadIfNeeded(relativePath: rel) {
                        completed += 1
                        progress(completed, total)
                        if completed == total { completion() }
                    }
                }
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
            completion(); return
        }
        guard let remote = remoteURL(forRelativePath: relativePath) else { completion(); return }
        let tmp = dest.appendingPathExtension("download")
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

