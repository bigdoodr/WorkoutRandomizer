# Apple Watch HealthKit Integration Setup Guide

This guide explains how to display HealthKit data from your Apple Watch on your iPhone app during active workout routines.

## Overview

The integration allows your iPhone app to:
- Display real-time heart rate from Apple Watch
- Show active calories burned during the workout
- Indicate when the Apple Watch workout session is active
- Receive automatic updates throughout the workout

## Files Created/Modified

### New Files Created:
1. **WorkoutConnectivityManager+iOS.swift** - iOS connectivity manager that receives health data from Watch
2. **HealthMetricsView.swift** - SwiftUI view component to display health metrics
3. **Info-HealthKit.plist** - Privacy descriptions for HealthKit access

### Modified Files:
1. **WorkoutSessionManager.swift** - Updated to send health metrics to iPhone
2. **WorkoutRandomizer.swift** - Updated WorkoutPlayerView to display health metrics

## Setup Instructions

### 1. Add HealthKit Capability

In Xcode:
1. Select your iOS app target
2. Go to "Signing & Capabilities" tab
3. Click "+ Capability"
4. Add "HealthKit"

For the Watch app target:
1. Select your watchOS app target
2. Go to "Signing & Capabilities" tab
3. Click "+ Capability"
4. Add "HealthKit"

### 2. Add Privacy Descriptions to Info.plist

Add the following keys to your iOS app's Info.plist:

```xml
<key>NSHealthShareUsageDescription</key>
<string>This app needs access to your health data to display workout metrics during your exercise routines.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>This app needs to save your workout data to HealthKit to track your fitness progress.</string>
```

For the Watch app, add to its Info.plist:

```xml
<key>NSHealthShareUsageDescription</key>
<string>This app tracks your heart rate and calories during workouts.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>This app saves workout data to HealthKit.</string>
```

### 3. Add Files to Your Target

Make sure these new files are added to the correct targets:
- **WorkoutConnectivityManager+iOS.swift** → iOS app target only
- **HealthMetricsView.swift** → iOS app target only
- **WorkoutSessionManager.swift** → watchOS app target only

### 4. Import the HealthMetricsView

The WorkoutPlayerView has already been updated to include the HealthMetricsView. No additional changes needed!

## How It Works

### Data Flow:

1. **User starts workout on iPhone**
   - iPhone sends workout state to Apple Watch via WatchConnectivity
   - iPhone attempts to launch Watch app with workout session

2. **Watch receives workout state**
   - User can start HealthKit workout tracking on Watch
   - WorkoutSessionManager begins collecting heart rate and calorie data

3. **Watch sends health metrics to iPhone**
   - Every time new health data is collected (typically every few seconds)
   - WorkoutSessionManager sends metrics via WatchConnectivity
   - Metrics include: heart rate (BPM), active calories (kcal), workout active status

4. **iPhone displays metrics**
   - WorkoutConnectivityManager receives and updates published properties
   - HealthMetricsView automatically updates with new data
   - Display only shows when workout is active and Watch is connected

## UI Components

### HealthMetricsView
A clean, card-based UI showing:
- **Heart Rate** - Real-time BPM with heart icon
- **Active Calories** - Total calories burned with flame icon
- **Status Indicator** - Shows if Watch workout is active (green) or inactive (gray)

The view automatically appears during active workouts when the Watch is connected.

## Troubleshooting

### Health data not showing:
1. Ensure HealthKit capability is added to both iOS and watchOS targets
2. Check that privacy descriptions are in both Info.plist files
3. Verify Watch is paired and connected to iPhone
4. Make sure workout session is started on Apple Watch

### Watch not receiving workout state:
1. Check WatchConnectivity session is active
2. Ensure Watch app is installed and active
3. Try restarting both iPhone and Apple Watch

### Data updates are slow:
- HealthKit data collection frequency is controlled by watchOS
- Typically updates every 3-5 seconds during active workouts
- Heart rate updates may be more frequent during intense activity

## Testing

### On Simulator:
- WatchConnectivity works between iOS and watchOS simulators
- HealthKit data will be simulated (not real)
- You can test the UI and connectivity flow

### On Device:
1. Install app on both iPhone and Apple Watch
2. Start a workout on iPhone
3. On Watch, tap to start HealthKit tracking when prompted
4. Begin exercising - heart rate and calories will update automatically
5. View real-time metrics on iPhone

## Privacy & Permissions

### HealthKit Authorization:
- Watch app requests authorization when first starting a workout
- User must grant permission for heart rate and calorie tracking
- Authorization persists across app launches

### Data Usage:
- Health data is only transmitted between your devices
- No health data is stored permanently by the app (only in HealthKit)
- Data transmission uses encrypted WatchConnectivity framework

## Code Examples

### Accessing Health Metrics in Your Code:

```swift
// In any SwiftUI view on iOS
@StateObject private var connectivityManager = WorkoutConnectivityManager.shared

var body: some View {
    VStack {
        Text("Heart Rate: \(Int(connectivityManager.heartRate)) BPM")
        Text("Calories: \(Int(connectivityManager.activeCalories)) kcal")
        
        if connectivityManager.isWatchWorkoutActive {
            Text("Watch workout active")
        }
    }
}
```

### Manually Starting Watch Workout:

```swift
// This is already called automatically when starting a workout
// But you can trigger it manually if needed
#if os(iOS)
let store = HKHealthStore()
let configuration = HKWorkoutConfiguration()
configuration.activityType = .highIntensityIntervalTraining
configuration.locationType = .indoor

store.startWatchApp(with: configuration) { success, error in
    if success {
        print("Watch app launched")
    }
}
#endif
```

## Architecture

### iOS Side:
- `WorkoutConnectivityManager` - ObservableObject that manages Watch communication
- `HealthMetricsView` - SwiftUI view component for displaying metrics
- `WorkoutPlayerView` - Main workout UI that includes HealthMetricsView

### watchOS Side:
- `WorkoutSessionManager` - Manages HealthKit workout sessions
- `WorkoutConnectivityManager` - Receives workout state from iPhone
- Sends health metrics back to iPhone via WatchConnectivity

### Communication Protocol:
Messages are sent as dictionaries with a "type" key:
- `"healthMetrics"` - Contains heart rate, calories, and workout status
- `"workoutState"` - Contains current exercise, timer, and progress
- `"timerUpdate"` - Real-time countdown updates
- `"control"` - Pause, resume, stop commands
- `"feedback"` - Haptic feedback triggers

## Future Enhancements

Potential improvements you could add:
- Display additional metrics (distance, pace, power)
- Show workout graphs and trends
- Add workout history from HealthKit
- Custom workout types for different exercises
- Export workout summaries
- Integration with other health metrics

## Support

For issues or questions:
1. Check that all files are in the correct targets
2. Verify HealthKit capabilities are enabled
3. Ensure privacy descriptions are in Info.plist
4. Test on real devices (not just simulator)

---

**Note**: This integration requires:
- iOS 16.0+ (for Swift Concurrency and modern WatchConnectivity)
- watchOS 9.0+ (for HealthKit workout sessions)
- Paired Apple Watch
- HealthKit capability enabled in both app targets
