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
        // A five-item bottom bar is an iPhone idiom. On the Mac and iPad this turns the same
        // tabs into a sidebar, which is what those platforms expect.
        #if os(macOS)
        .tabViewStyle(.sidebarAdaptable)
        #endif
    }
}
