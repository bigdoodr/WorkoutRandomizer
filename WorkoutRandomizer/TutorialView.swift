//  TutorialView.swift
//  Bodyweight WorkoutRandomizer
//
//  The onboarding guide — both the full tour and the shorter "what's new" run.
//
//  Every page records the version its feature arrived in. That one field is what lets the same
//  view serve two jobs: show everything to someone opening the app for the first time, and show
//  only the genuinely new pages to someone who has already been here. Adding a feature in a
//  future release means adding a page and tagging it with that release — the filtering below
//  needs no further edits.
//
//  Who sees what is decided by `lastSeenTutorialVersion`, which is written when the guide is
//  finished or skipped. An empty value means the guide has never been completed under the
//  version-aware scheme, which covers both a fresh install and every 1.x user upgrading to 2.0 —
//  both get the full tour, which is exactly what the 2.0 release wants.

import SwiftUI

// MARK: - TutorialView

struct TutorialView: View {
    /// Which run of the guide this is.
    enum Mode: Equatable {
        /// Every page. First launch, or requested from Settings.
        case full
        /// Only pages introduced after the given version.
        case whatsNew(since: String)

        var id: String {
            switch self {
            case .full: return "full"
            case .whatsNew(let since): return "whatsNew-\(since)"
            }
        }
    }

    var mode: Mode = .full

    @AppStorage("lastSeenTutorialVersion") private var lastSeenTutorialVersion = ""
    @State private var page = 0
    @Environment(\.dismiss) private var dismiss

    private struct TutorialPage {
        let title: String
        let body: String
        let icon: String
        let color: Color
        /// App version this page's subject arrived in. Drives what a returning user still needs.
        var since: String = "1.0"
        /// A release summary rather than a feature explanation. Only worth showing while its
        /// release is the current one — a 3.0 user meeting the app for the first time has no
        /// use for "What's New in 2.0".
        var isReleaseOverview: Bool = false
    }

    // Static so the filtering below — and the caller's "is there anything new?" check — can run
    // without standing up a view.
    private static let allPages: [TutorialPage] = [
        TutorialPage(
            title: "What's New in 2.0",
            body: "The biggest update yet: a five-tab layout, two new ladder timer styles, Pyramid workouts that fit the length you asked for, optional warm-ups and cool-downs matched to your focus, video demos in the stretch player, and a proper Settings screen. The next few pages cover all of it.",
            icon: "sparkles", color: .indigo, since: "2.0", isReleaseOverview: true
        ),
        TutorialPage(
            title: "Welcome & Your Goal",
            body: "Generate custom bodyweight workouts tailored to your focus areas, difficulty, and equipment. Tell the app your goal — Fat Burn, Cardio Endurance, Strength, or General Fitness — and tap your HR Zone during a workout for tips matched to it.",
            icon: "figure.run", color: .blue, since: "1.0"
        ),
        TutorialPage(
            title: "Customize Every Session",
            body: "Tap the icon chips to choose focus areas — one or many. Difficulty is multi-select too, so a session can mix Beginner and Medium. Tell the app what equipment you have and it only draws from moves you can do. Prefer just stretching? The Stretch tab runs a hold-based session of its own, with video demos.",
            icon: "figure.mixed.cardio", color: .purple, since: "1.0"
        ),
        TutorialPage(
            title: "Getting Around & Settings",
            body: "Five tabs along the bottom. Generate builds a workout. Exercises browses the whole catalog with demo videos. Stretch runs a stretch-only session. Saved holds curated routines and your own. My Exercises is for moves you add yourself. The gear button opens Settings, where video, sound, and haptics all stick between launches — and you can reopen this guide any time.",
            icon: "square.grid.2x2.fill", color: .cyan, since: "2.0"
        ),
        TutorialPage(
            title: "Timer & Pacing Options",
            body: "Standard runs a steady work/rest cycle. Pyramid ramps up and back down across the length you picked. Repeating Blocks cycles the same group of exercises. Add-On builds a ladder; Add-On + Take Away climbs then peels back off. Switch on a warm-up or cool-down in the Generate tab — both drawn from stretches matching your focus. Need one exercise longer than the rest? Custom Timers lets you set any slot by hand, and it follows the routine everywhere — playback, Watch, and anything you save.",
            icon: "timer", color: .green, since: "2.0"
        ),
        TutorialPage(
            title: "Saved & Shared Routines",
            body: "The Saved tab has curated workouts — Athlean-X morning stretches, a bedtime routine, and a 10-minute ab circuit — each with per-exercise timers built in. Anything you generate can be saved there under My Routines, or exported to a file and imported back later.",
            icon: "folder.fill", color: .brown, since: "1.4"
        ),
        TutorialPage(
            title: "Track Your Progress",
            body: "Add your own moves in My Exercises with a name, focus area, and difficulty — they join the pool the generator draws from. While a workout runs you get live exercise time, heart-rate zone, and burn type; the recap after shows total and working time, calories, and peak/average heart rate.",
            icon: "chart.bar.fill", color: .mint, since: "1.3"
        ),
        TutorialPage(
            title: "Apple Watch",
            body: "Pair your Apple Watch for live heart rate, zone, and calorie data. You can start and stop a session from your wrist, and the Watch status line below the Start button always shows where the connection stands.",
            icon: "applewatch", color: .red, since: "1.1"
        ),
    ]

    /// The pages a given run should show.
    private static func pages(for mode: Mode) -> [TutorialPage] {
        allPages.filter { page in
            if page.isReleaseOverview,
               AppVersion.compare(page.since, AppVersion.current) != .orderedSame {
                return false
            }
            switch mode {
            case .full:
                return true
            case .whatsNew(let since):
                return AppVersion.isNewer(page.since, than: since)
            }
        }
    }

    private var pages: [TutorialPage] { Self.pages(for: mode) }

    /// Whether a "what's new" run for someone last shown `version` would have anything to say.
    /// The caller checks this before presenting, so a dot release that documents nothing new
    /// doesn't greet everyone with an empty guide.
    static func hasPages(newerThan version: String) -> Bool {
        !pages(for: .whatsNew(since: version)).isEmpty
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
