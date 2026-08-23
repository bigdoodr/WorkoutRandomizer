//  SettingsView.swift
//  Bodyweight WorkoutRandomizer
//
//  Feedback and video preferences, previously buried behind the generator's Advanced toggle.
//
//  Everything here is `@AppStorage`, which is both how it persists and how it reaches the rest
//  of the app: the generator reads the same keys, so a change made in this sheet is visible
//  everywhere without any plumbing between the two.
//
//  Worth noting the three feedback flags used to be plain `@State` on the generator, which meant
//  sounds and haptics silently switched themselves back on at every launch. Giving them real
//  storage is the actual fix; moving them here is just where they belong.

import SwiftUI

struct SettingsView: View {
    @AppStorage("enableSound_iOS_tv_vision") private var enableSound_iOS_tv_vision = true
    @AppStorage("enableHaptics_iOS_vision") private var enableHaptics_iOS_vision = true
    @AppStorage("enableSound_macOS") private var enableSound_macOS = true
    @AppStorage("videoMode") private var videoModeRaw: String = VideoMode.stream.rawValue

    @StateObject private var videoManager = VideoManager.shared
    @State private var downloadProgress: (completed: Int, total: Int)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
#if os(iOS) || os(tvOS) || os(visionOS)
                    Toggle(isOn: $enableSound_iOS_tv_vision) {
                        Label("Sounds", systemImage: enableSound_iOS_tv_vision ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
#endif
#if os(iOS)
                    Toggle(isOn: $enableHaptics_iOS_vision) {
                        Label("Haptics", systemImage: enableHaptics_iOS_vision ? "hand.tap.fill" : "hand.raised")
                    }
#endif
#if os(macOS)
                    Toggle(isOn: $enableSound_macOS) {
                        Label("Sounds", systemImage: enableSound_macOS ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
#endif
                } header: {
                    Text("Feedback")
                } footer: {
                    Text("Cues when an exercise starts, is about to end, and when the routine finishes.")
                }

                Section {
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
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Downloading \(progress.completed) of \(progress.total)…")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Button("Download Videos") { startVideoDownload() }
                        }
                    }
                } header: {
                    Text("Video")
                } footer: {
                    Text("Stream plays demos over the network. Download All keeps them on device for offline workouts.")
                }
            }
            .navigationTitle("Settings")
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

    private func startVideoDownload() {
        downloadProgress = (completed: 0, total: videoManager.videoPaths.count)
        videoManager.downloadAllKnownVideos(progress: { completed, total in
            downloadProgress = (completed: completed, total: total)
        }, completion: {
            downloadProgress = nil
        })
    }
}
