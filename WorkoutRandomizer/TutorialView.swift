//  TutorialView.swift
//  Bodyweight WorkoutRandomizer
//
//  The onboarding guide — a short tour for newcomers, and a "What's New" run for returning users.
//
//  Two kinds of page, kept apart on purpose:
//   • Tour pages describe the app as it is today. They carry no version, are rewritten whenever
//     the app changes, and make up the full guide. Keep it short: a handful of pages, each
//     covering one idea.
//   • Update pages announce one change and are tagged with the release they first shipped in —
//     a version *and* a build (`AppRelease`). They never appear in the tour; they exist only to
//     tell someone who already knows the app what changed since they last looked.
//
//  What a returning user sees is every update page tagged after the last release they were
//  walked through (and no later than the one running). The last-seen release is written when the
//  guide is finished or skipped. Nothing recorded means a fresh install — or an upgrade from
//  before this tracking — and gets the full tour. A release with no newer update pages passes in
//  silence.
//
//  To document a new feature: add an update page to `updatePages` below, tagged with the version
//  and the build number it will first ship in. Nothing else needs to change. Builds are only
//  compared within a version, so a number that restarts per version works as well as one that
//  keeps climbing; when unsure, tag the build you're about to upload.

import SwiftUI

// MARK: - TutorialView

struct TutorialView: View {
    /// Which run of the guide this is.
    enum Mode: Equatable {
        /// The tour. First launch, or requested from Settings.
        case full
        /// Only update pages tagged after the given release.
        case whatsNew(since: AppRelease)

        var id: String {
            switch self {
            case .full: return "full"
            case .whatsNew(let since): return "whatsNew-\(since.displayName)"
            }
        }
    }

    var mode: Mode = .full

    @AppStorage("lastSeenTutorialVersion") private var lastSeenTutorialVersion = ""
    @AppStorage("lastSeenTutorialBuild") private var lastSeenTutorialBuild = 0
    @State private var page = 0
    @Environment(\.dismiss) private var dismiss

    private struct TutorialPage {
        let title: String
        let body: String
        let icon: String
        let color: Color
        /// The release an update page first shipped in. Nil for tour pages.
        var since: AppRelease? = nil
    }

    // MARK: Tour

    private static let tourPages: [TutorialPage] = [
        TutorialPage(
            title: "Build a Workout",
            body: "Pick a goal, then tap the icon chips for focus areas, difficulty and the equipment you have. Generate draws a balanced session from moves that match. Prefer stretching? Flip the picker at the top of Generate to Stretch. Want to choose the moves yourself? Set Source to My List.",
            icon: "figure.mixed.cardio", color: .blue
        ),
        TutorialPage(
            title: "Set the Pace",
            body: "The Timer tab controls how a session runs: timer style (Standard, Pyramid, Repeating Blocks or an Add-On ladder), work and rest times, and an optional warm-up and cool-down. After generating, Custom Timers lets you change any single exercise's time.",
            icon: "timer", color: .green
        ),
        TutorialPage(
            title: "Find, Save & Share",
            body: "Exercises is the full catalog with demo videos — Library for built-in moves, Mine for your own. Swipe or long-press any move to add it to a routine you're building. Saved keeps routines in folders; save anything you generate or build, and export a routine to a file to share it.",
            icon: "list.bullet.rectangle.portrait", color: .purple
        ),
        TutorialPage(
            title: "Train & Track",
            body: "While you work out you'll see live exercise time, heart-rate zone and burn type, and the recap shows time, calories and heart rate. Pair an Apple Watch for live heart rate and to start or pause from your wrist. In Settings, add your age for accurate zones, tune video and sound, or reopen this guide.",
            icon: "applewatch", color: .red
        ),
    ]

    // MARK: Updates

    private static let updatePages: [TutorialPage] = [
        TutorialPage(
            title: "Build Your Own & Favorites",
            body: "Assemble a routine move by move with Build Your Own, and star favorites so they're easy to find. There's a new HIIT intention, longer rests between full Repeating Blocks cycles, and pause and skip controls on Apple Watch.",
            icon: "plus.rectangle.on.rectangle", color: .orange, since: AppRelease("2.1")
        ),
        TutorialPage(
            title: "Heart-Rate Zones",
            body: "Zones now follow you. Add your age in Settings and heart-rate zones, live tips and the recap all use your own numbers. A badge on the Settings tab shows until you've set it.",
            icon: "heart.text.square", color: .pink, since: AppRelease("2.2")
        ),
        TutorialPage(
            title: "Timer Tab & My List",
            body: "Timer style, durations, rest and warm-up/cool-down now live on their own Timer tab. On Generate, set Source to My List to run the moves you queued — all of them in order, or draw from them. Stretch is now a picker on Generate, and My Exercises is the Mine side of Exercises.",
            icon: "timer", color: .green, since: AppRelease("2.3")
        ),
        TutorialPage(
            title: "Folders, Sharing & Recaps",
            body: "Saving now asks for a name and a folder. Saved sorts routines into folders, stretches can be saved too, and import and export sit right in the Saved tab. Workouts reach Apple Health as the right type — Flexibility, Core or Mixed Cardio — and Core-only recaps skip the alignment score.",
            icon: "folder.fill", color: .brown, since: AppRelease("2.3")
        ),
    ]

    /// The pages a given run should show.
    private static func pages(for mode: Mode) -> [TutorialPage] {
        switch mode {
        case .full:
            return tourPages
        case .whatsNew(let seen):
            let current = AppRelease.current
            // Oldest first, so a long absence reads as a story. `sorted` is stable, so pages
            // tagged with the same release stay in the order they're written above.
            let fresh = updatePages
                .filter { page in
                    guard let release = page.since else { return false }
                    return release > seen && release <= current
                }
                .sorted { ($0.since ?? current) < ($1.since ?? current) }
            // One page needs no introduction; several get a summary of the range they cover.
            guard fresh.count > 1 else { return fresh }
            return [overview(for: fresh, since: seen)] + fresh
        }
    }

    /// The opening page of a multi-page "What's New", worded from the range being shown.
    private static func overview(for fresh: [TutorialPage], since seen: AppRelease) -> TutorialPage {
        let versions = fresh.compactMap { $0.since?.version }
        let distinct = versions.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let range = distinct.count == 1
            ? "in \(distinct[0])"
            : "since \(seen.version)"
        return TutorialPage(
            title: "What's New",
            body: "Here's what's changed \(range) — \(fresh.count) quick pages.",
            icon: "sparkles", color: .indigo
        )
    }

    private var pages: [TutorialPage] { Self.pages(for: mode) }

    /// Whether a "what's new" run for someone last shown `release` would have anything to say.
    /// The caller checks this before presenting, so a release that documents nothing new
    /// doesn't greet everyone with an empty guide.
    static func hasPages(newerThan release: AppRelease) -> Bool {
        !pages(for: .whatsNew(since: release)).isEmpty
    }

    /// The release the user last finished the guide under, or nil if they never have.
    static func lastSeenRelease(version: String, build: Int) -> AppRelease? {
        version.isEmpty ? nil : AppRelease(version, build: build)
    }

    private var navigationTitle: String {
        switch mode {
        case .full: return "Welcome to WorkoutRandomizer"
        case .whatsNew: return "What's New"
        }
    }

    /// Dots get thin once there are a lot of them, so a full-length guide's indicator still
    /// fits across a phone.
    private var indicatorWidth: CGFloat { pages.count > 9 ? 10 : 24 }

    private func finish() {
        lastSeenTutorialVersion = AppVersion.current
        lastSeenTutorialBuild = AppVersion.currentBuild
        dismiss()
    }

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
                                .frame(width: indicatorWidth, height: 4)
                                // A 4pt-tall dot is far too small to aim at; give it a real
                                // touch target without changing how it looks.
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
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
                .padding(.bottom, 12)
            }
            .navigationTitle(navigationTitle)
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip") { finish() }
                }
            }
#else
            .toolbar {
                ToolbarItem { Button("Skip") { finish() } }
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
                .multilineTextAlignment(.center)
            Text(p.body)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            if index == pages.count - 1 {
                Button(mode == .full ? "Get Started" : "Done") { finish() }
                    .buttonStyle(.borderedProminent)
                    .tint(p.color)
                    .controlSize(.large)
            }
            Spacer(minLength: 50)
        }
    }
}
