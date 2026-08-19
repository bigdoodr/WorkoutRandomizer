//  TutorialView.swift
//  Bodyweight WorkoutRandomizer
//
//  First-launch onboarding walkthrough.
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

// MARK: - TutorialView

struct TutorialView: View {
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
    @State private var page = 0
    @Environment(\.dismiss) private var dismiss

    private struct TutorialPage {
        let title: String
        let body: String
        let icon: String
        let color: Color
    }

    private let pages: [TutorialPage] = [
        TutorialPage(title: "Welcome!", body: "Generate custom bodyweight workouts tailored to your focus areas, difficulty level, and available equipment.", icon: "figure.run", color: .blue),
        TutorialPage(title: "Focus & Equipment", body: "Tap the icon chips to choose which muscle groups to target. Select one or many — the generated workout will draw from those areas. Pick the equipment you have available too.", icon: "figure.mixed.cardio", color: .purple),
        TutorialPage(title: "Saved Routines", body: "Tap 'Saved Routines' on the home screen for expertly curated workouts, including Athlean-X morning stretches, bedtime stretches, and a 10-minute ab routine — each with per-exercise timers built in.", icon: "folder.fill", color: .brown),
        TutorialPage(title: "Audio & Video", body: "Exercise videos stream by default over Wi-Fi/cellular. In Advanced mode you can pre-download them for offline use or disable video entirely. Audio countdown cues play automatically — set your phone to ring (not silent) for sound.", icon: "play.rectangle.fill", color: .pink),
        TutorialPage(title: "Stretch Routine", body: "The Stretch Routine section is completely separate from regular workouts. Set hold duration, choose your categories, and optionally cap the total time — no cardio-style rest intervals.", icon: "figure.cooldown", color: .teal),
        TutorialPage(title: "Set Your Intention", body: "Tell the app your goal — Fat Burn, Cardio Endurance, Strength, or General Fitness. During workouts, tap your HR Zone for personalized zone tips.", icon: "flame", color: .orange),
        TutorialPage(title: "Apple Watch", body: "Pair your Apple Watch to see live heart rate, HR zone, and calorie data. The Watch status bar below the Start button always shows connection state — look for 'Watch Connected' or 'You can also start from your Apple Watch'.", icon: "applewatch", color: .red),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
#if os(macOS)
                pageContent(for: page)
                    .id(page)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if page < pages.count - 1 {
                            withAnimation(.easeInOut(duration: 0.3)) { page += 1 }
                        }
                    }
#else
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, _ in
                        pageContent(for: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
#endif
                HStack(spacing: 16) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { page -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(page == 0)
                    .opacity(page == 0 ? 0.25 : 1)

                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { i in
                            Capsule()
                                .fill(i == page ? Color.primary : Color.secondary.opacity(0.25))
                                .frame(width: 24, height: 4)
                                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { page = i } }
                        }
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { page += 1 }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(page == pages.count - 1)
                    .opacity(page == pages.count - 1 ? 0.25 : 1)
                }
                .padding(.bottom, 20)
            }
            .navigationTitle("Welcome to WorkoutRandomizer")
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip") { hasSeenTutorial = true; dismiss() }
                }
            }
#else
            .toolbar {
                ToolbarItem { Button("Skip") { hasSeenTutorial = true; dismiss() } }
            }
#endif
        }
    }

    @ViewBuilder
    private func pageContent(for index: Int) -> some View {
        let p = pages[index]
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: p.icon)
                .font(.system(size: 72))
                .foregroundStyle(p.color)
            Text(p.title)
                .font(.title)
                .fontWeight(.bold)
            Text(p.body)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            if index == pages.count - 1 {
                Button("Get Started") {
                    hasSeenTutorial = true
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(p.color)
                .controlSize(.large)
            }
            Spacer(minLength: 50)
        }
    }
}
