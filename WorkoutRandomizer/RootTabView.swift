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
    /// Owned here rather than per-tab so the generator and the exercise browser read the same
    /// catalog instance, and a remote refresh updates every tab at once.
    @State private var catalog = ExerciseCatalog.shared
    @State private var selection: AppTab = .generator
    // Regular width means an iPad-sized layout, or the inner display of a dual-screen iPhone —
    // both want the sidebar. iPhone's outer display and a folded dual-screen iPhone are compact
    // and keep the familiar bottom tab bar.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    enum AppTab: Hashable {
        case generator, allExercises, stretch, saved, myExercises
    }

    var body: some View {
        TabView(selection: $selection) {
            // The generator supplies its own NavigationStack already.
            Tab("Generate", systemImage: "figure.mixed.cardio", value: AppTab.generator) {
                WorkoutGeneratorView()
            }

            // The remaining four were only ever pushed from the generator, so none of them
            // carries a NavigationStack of its own — each tab has to provide one or their
            // navigation titles and toolbars have nothing to attach to.
            Tab("Exercises", systemImage: "list.bullet.rectangle.portrait", value: AppTab.allExercises) {
                NavigationStack {
                    ExercisesView(exercisesByArea: catalog.exercises)
                }
            }

            Tab("Stretch", systemImage: "figure.cooldown", value: AppTab.stretch) {
                NavigationStack {
                    StretchRoutineView()
                }
            }

            Tab("Saved", systemImage: "folder.fill", value: AppTab.saved) {
                NavigationStack {
                    SavedRoutinesView()
                }
            }

            Tab("My Exercises", systemImage: "person.badge.plus", value: AppTab.myExercises) {
                NavigationStack {
                    MyExercisesView(
                        focusAreas: catalog.focusAreas,
                        difficulties: catalog.difficulties
                    )
                }
            }
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
        #endif
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
}
#endif
