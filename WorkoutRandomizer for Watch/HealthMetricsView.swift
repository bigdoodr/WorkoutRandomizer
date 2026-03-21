// HealthMetricsView.swift
// Displays HealthKit metrics from Apple Watch during workout

#if os(iOS)
import SwiftUI

struct HealthMetricsView: View {
    @ObservedObject var connectivityManager: WorkoutConnectivityManager
    
    var body: some View {
        VStack(spacing: 12) {
            // Title
            HStack {
                Image(systemName: "applewatch")
                    .foregroundColor(.blue)
                Text("Apple Watch Metrics")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            // Metrics Display
            HStack(spacing: 30) {
                // Heart Rate
                MetricCard(
                    icon: "heart.fill",
                    iconColor: .red,
                    value: Int(connectivityManager.heartRate),
                    unit: "BPM",
                    label: "Heart Rate"
                )
                
                // Active Calories
                MetricCard(
                    icon: "flame.fill",
                    iconColor: .orange,
                    value: Int(connectivityManager.activeCalories),
                    unit: "kcal",
                    label: "Calories"
                )
            }
            
            // Watch Status Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(connectivityManager.isWatchWorkoutActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(connectivityManager.isWatchWorkoutActive ? "Watch workout active" : "No active workout")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
}

struct MetricCard: View {
    let icon: String
    let iconColor: Color
    let value: Int
    let unit: String
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(value)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
    HealthMetricsView(connectivityManager: WorkoutConnectivityManager.shared)
        .padding()
}
#endif
