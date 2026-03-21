//
//  HealthKitDebugView.swift
//  Debug view to test HealthKit connectivity and metrics
//
//  This view is useful for testing the Watch-to-iPhone health metrics flow
//  Add it to your app during development to verify everything is working
//

#if os(iOS) && DEBUG
import SwiftUI

struct HealthKitDebugView: View {
    @StateObject private var connectivityManager = WorkoutConnectivityManager.shared
    @State private var showingTestMetrics = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("Connection Status") {
                    StatusRow(
                        label: "Watch Connected",
                        value: connectivityManager.isWatchConnected,
                        icon: "applewatch"
                    )
                    StatusRow(
                        label: "Watch Workout Active",
                        value: connectivityManager.isWatchWorkoutActive,
                        icon: "figure.run"
                    )
                }
                
                Section("Live Metrics") {
                    MetricRow(
                        label: "Heart Rate",
                        value: "\(Int(connectivityManager.heartRate))",
                        unit: "BPM",
                        icon: "heart.fill",
                        iconColor: .red
                    )
                    MetricRow(
                        label: "Active Calories",
                        value: "\(Int(connectivityManager.activeCalories))",
                        unit: "kcal",
                        icon: "flame.fill",
                        iconColor: .orange
                    )
                }
                
                Section("Visual Preview") {
                    HealthMetricsView(connectivityManager: connectivityManager)
                        .padding(.vertical, 8)
                }
                
                Section("Instructions") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Testing Steps:")
                            .font(.headline)
                        
                        InstructionStep(
                            number: 1,
                            text: "Ensure Apple Watch is paired and nearby"
                        )
                        InstructionStep(
                            number: 2,
                            text: "Start a workout from the main app"
                        )
                        InstructionStep(
                            number: 3,
                            text: "On your Watch, start the HealthKit workout tracking"
                        )
                        InstructionStep(
                            number: 4,
                            text: "Watch this view update with real-time metrics"
                        )
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Troubleshooting") {
                    DisclosureGroup("Watch not connecting?") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• Check Watch is paired in the Watch app")
                            Text("• Ensure WatchConnectivity is activated")
                            Text("• Try restarting both iPhone and Watch")
                            Text("• Verify Watch app is installed")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                    }
                    
                    DisclosureGroup("No metrics showing?") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• Ensure HealthKit capability is enabled")
                            Text("• Check Info.plist has privacy descriptions")
                            Text("• Verify workout session started on Watch")
                            Text("• Grant HealthKit permissions when prompted")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                    }
                    
                    DisclosureGroup("Data not updating?") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• Start exercising to generate heart rate data")
                            Text("• HealthKit updates every 3-5 seconds")
                            Text("• Check WorkoutSessionManager is running")
                            Text("• Verify sendHealthMetricsToPhone() is called")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("HealthKit Debug")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct StatusRow: View {
    let label: String
    let value: Bool
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            Text(label)
            
            Spacer()
            
            HStack(spacing: 6) {
                Circle()
                    .fill(value ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                Text(value ? "Yes" : "No")
                    .font(.subheadline)
                    .foregroundColor(value ? .green : .secondary)
            }
        }
    }
}

struct MetricRow: View {
    let label: String
    let value: String
    let unit: String
    let icon: String
    let iconColor: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            Text(label)
            
            Spacer()
            
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct InstructionStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.blue)
                .frame(width: 20, alignment: .leading)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    HealthKitDebugView()
}
#endif
