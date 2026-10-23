//  RootTabView.swift
//  Bodyweight WorkoutRandomizer
//
//  The app's five-tab shell. Replaces the four coloured NavigationLink buttons that used to sit
//  at the top of the generator screen — those pushed each destination onto the generator's own
//  navigation stack, which meant every other screen was reached *through* the generator rather
//  than alongside it.
//
//  Liquid Glass is adopted implicitly: this is a stock TabView, so when built against the
//  Xcode 26 SDK it picks up the system treatment on iOS 26 and degrades cleanly on the 18.6
//  deployment target. There is deliberately no `#available` gating and no custom `.glassEffect`.

import SwiftUI

struct RootTabView: View {
    @State private var selection: AppTab = .generator
    // Regular width means an iPad-sized layout, or the inner display of a dual-screen iPhone —
    // both want the sidebar. iPhone's outer display and a folded dual-screen iPhone are compact
    // and keep the familiar bottom tab bar.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Shared across every tab: swiping or long-pressing an exercise in Exercises/My Exercises
    // appends here, and this mini-player-style bar (shown above the tab bar) opens the builder
    // pre-loaded with whatever's queued. See BuildYourOwnRoutineView.swift.
    @State private var queue = RoutineBuilderQueue.shared
    @State private var showingBuilder = false

    @State private var hrZones = HRZoneSettings.shared

    enum AppTab: Hashable {
        case generator, timer, exercises, saved, settings
    }

    var body: some View {
        TabView(selection: $selection) {
            // None of the tab root views carries a NavigationStack of its own — each tab has
            // to provide one or their navigation titles and toolbars have nothing to attach
            // to. (SettingsView is the exception: it already wraps itself in one.)
            Tab("Generate", systemImage: "figure.mixed.cardio", value: AppTab.generator) {
                NavigationStack {
                    GenerateHubView(onOpenTimer: { selection = .timer })
                }
                .applyingQueueBarFallback(queue: queue, showingBuilder: $showingBuilder)
            }

            // Timer style, durations, rest and warm-up/cool-down for generated workouts.
            Tab("Timer", systemImage: "timer", value: AppTab.timer) {
                TimerSettingsView()
                    .applyingQueueBarFallback(queue: queue, showingBuilder: $showingBuilder)
            }

            Tab("Exercises", systemImage: "list.bullet.rectangle.portrait", value: AppTab.exercises) {
                NavigationStack {
                    ExercisesHubView()
                }
                .applyingQueueBarFallback(queue: queue, showingBuilder: $showingBuilder)
            }

            Tab("Saved", systemImage: "folder.fill", value: AppTab.saved) {
                NavigationStack {
                    SavedRoutinesView()
                }
                .applyingQueueBarFallback(queue: queue, showingBuilder: $showingBuilder)
            }

            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
                    .applyingQueueBarFallback(queue: queue, showingBuilder: $showingBuilder)
            }
            .badge(hrZones.isAgeMissing ? Text("!") : nil)
        }
        // A five-item bottom bar is the compact-width idiom. On the Mac, iPad, and the inner
        // display of a dual-screen iPhone, the same tabs become a sidebar instead.
        //
        // iPadOS already morphs sidebarAdaptable between a top bar and a sidebar on its own as
        // its size class changes, so defaultTabBarPlacement below has no effect there. iPhone —
        // including a dual-screen iPhone's inner/outer displays — only ever shows one fixed
        // representation at a time, so it needs to be told explicitly which one to use.
        #if os(macOS)
        .tabViewStyle(.sidebarAdaptable)
        #elseif os(iOS)
        .tabViewStyle(.sidebarAdaptable)
        .applyingDefaultTabBarPlacement(horizontalSizeClass: horizontalSizeClass)
        .applyingQueueBarAccessory(queue: queue, showingBuilder: $showingBuilder)
        #endif
        .sensoryFeedback(.success, trigger: queue.items.count)
        .sheet(isPresented: $showingBuilder) {
            BuildYourOwnRoutineView()
        }
    }
}

/// Generate tab: the workout generator and the stretch generator behind a Workout | Stretch
/// picker. Both stay alive and the unselected one is just hidden — the workout generator
/// holds ~30 settings plus the generated routine, and rebuilding it on each switch would wipe
/// them. That's safe here because neither screen contributes toolbar items; if one ever does,
/// hiding it won't hide its toolbar and this will need a different approach.
private struct GenerateHubView: View {
    private enum Segment: String, CaseIterable, Identifiable {
        case workout = "Workout"
        case stretch = "Stretch"
        var id: String { rawValue }
    }

    /// Opens the Timer tab (the workout generator's summary row calls it).
    var onOpenTimer: () -> Void = {}

    @State private var segment: Segment = .workout

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            ZStack {
                WorkoutGeneratorView(onOpenTimer: onOpenTimer)
                    .opacity(segment == .workout ? 1 : 0)
                    .allowsHitTesting(segment == .workout)
                    .accessibilityHidden(segment != .workout)
                StretchRoutineView()
                    .opacity(segment == .stretch ? 1 : 0)
                    .allowsHitTesting(segment == .stretch)
                    .accessibilityHidden(segment != .stretch)
            }
        }
        .navigationTitle(segment == .workout ? "Workout Generator" : "Stretch Routine")
    }
}

#if os(iOS)
private extension View {
    /// `defaultTabBarPlacement` ships in iOS 27 alongside dual-screen iPhone support; this app's
    /// deployment target predates it, so fall back to the plain bottom tab bar on older iOS.
    @ViewBuilder
    func applyingDefaultTabBarPlacement(horizontalSizeClass: UserInterfaceSizeClass?) -> some View {
        if #available(iOS 27.0, *) {
            self.defaultTabBarPlacement(horizontalSizeClass == .regular ? .sidebar : .tabBar)
        } else {
            self
        }
    }

    /// `tabViewBottomAccessory` ships in iOS 26.1 as the same system slot Music/Podcasts use for
    /// their mini-player, shown above the tab bar. On older iOS, each tab's own content falls
    /// back to a plain `safeAreaInset` bar instead (`applyingQueueBarFallback` below).
    @ViewBuilder
    func applyingQueueBarAccessory(queue: RoutineBuilderQueue, showingBuilder: Binding<Bool>) -> some View {
        if #available(iOS 26.1, *) {
            self.tabViewBottomAccessory(isEnabled: !queue.items.isEmpty) {
                RoutineQueueBar(queue: queue) { showingBuilder.wrappedValue = true }
            }
        } else {
            self
        }
    }
}
#endif

private extension View {
    /// Pre-iOS-26.1 and macOS have no system bottom-accessory slot, so the queue bar is pinned
    /// to each tab's own content via `safeAreaInset` instead — applying it to the `TabView`
    /// itself would place the bar underneath the tab bar/sidebar rather than above it.
    @ViewBuilder
    func applyingQueueBarFallback(queue: RoutineBuilderQueue, showingBuilder: Binding<Bool>) -> some View {
        #if os(iOS)
        if #available(iOS 26.1, *) {
            self
        } else {
            safeAreaInset(edge: .bottom) {
                if !queue.items.isEmpty {
                    RoutineQueueBar(queue: queue) { showingBuilder.wrappedValue = true }
                        .background(.bar)
                }
            }
        }
        #else
        safeAreaInset(edge: .bottom) {
            if !queue.items.isEmpty {
                RoutineQueueBar(queue: queue) { showingBuilder.wrappedValue = true }
                    .background(.bar)
            }
        }
        #endif
    }
}
