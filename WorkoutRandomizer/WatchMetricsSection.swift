//  WatchMetricsSection.swift
//  Bodyweight WorkoutRandomizer
//
//  The Apple Watch slot in the workout players: the full metrics panel while a Watch workout is
//  actually running and reachable, and a one-line hint otherwise. The panel used to show whenever
//  a Watch was merely paired, which meant a screenful of zeros for anyone not wearing one.

#if os(iOS)
import SwiftUI

struct WatchMetricsSection: View {
    @ObservedObject var connectivityManager: WorkoutConnectivityManager

    var body: some View {
        if connectivityManager.hasLiveWatchSession {
            HealthMetricsView(connectivityManager: connectivityManager)
        } else {
            Label("Wear Apple Watch for live heart rate", systemImage: "applewatch")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
    }
}
#endif
