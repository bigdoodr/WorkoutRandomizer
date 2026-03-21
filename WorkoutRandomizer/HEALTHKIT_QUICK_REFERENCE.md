# HealthKit Integration Quick Reference

## Key Points Summary

### ✅ What's Been Done

1. **iOS Connectivity Manager** (`WorkoutConnectivityManager+iOS.swift`)
   - Receives health metrics from Apple Watch
   - Published properties: `heartRate`, `activeCalories`, `isWatchWorkoutActive`
   - Automatically updates in real-time during workouts

2. **Watch Metrics Sender** (`WorkoutSessionManager.swift`)
   - Sends heart rate and calories to iPhone
   - Automatically transmits when new data is collected
   - Uses WatchConnectivity for reliable delivery

3. **UI Component** (`HealthMetricsView.swift`)
   - Beautiful card-based display
   - Shows heart rate (BPM) and calories (kcal)
   - Status indicator for Watch workout session
   - Auto-appears during active workouts

4. **Integration** (`WorkoutRandomizer.swift`)
   - HealthMetricsView integrated into WorkoutPlayerView
   - Only displays when workout is active and Watch is connected
   - Seamless user experience

### 📋 What You Need To Do

#### In Xcode Project Settings:

**For iOS App Target:**
1. Add HealthKit capability (Signing & Capabilities → + Capability → HealthKit)
2. Add to Info.plist:
   ```xml
   <key>NSHealthShareUsageDescription</key>
   <string>Display workout metrics during routines</string>
   <key>NSHealthUpdateUsageDescription</key>
   <string>Save workout data to HealthKit</string>
   ```

**For watchOS App Target:**
1. Add HealthKit capability
2. Add to Info.plist:
   ```xml
   <key>NSHealthShareUsageDescription</key>
   <string>Track heart rate and calories during workouts</string>
   <key>NSHealthUpdateUsageDescription</key>
   <string>Save workout sessions to HealthKit</string>
   ```

#### File Target Membership:
- Ensure `WorkoutConnectivityManager+iOS.swift` is in iOS target only
- Ensure `HealthMetricsView.swift` is in iOS target only
- Ensure `WorkoutSessionManager.swift` is in watchOS target only

### 🔄 How Data Flows

```
iPhone (WorkoutPlayerView)
    ↓
    Starts workout → Sends workout state to Watch
    ↓
Apple Watch (WorkoutSessionManager)
    ↓
    Collects heart rate & calories from HealthKit
    ↓
    Sends metrics to iPhone every few seconds
    ↓
iPhone (WorkoutConnectivityManager)
    ↓
    Updates published properties
    ↓
iPhone (HealthMetricsView)
    ↓
    Automatically refreshes UI with latest data
```

### 🎯 Testing Checklist

- [ ] Add HealthKit capability to iOS target
- [ ] Add HealthKit capability to watchOS target
- [ ] Add privacy descriptions to iOS Info.plist
- [ ] Add privacy descriptions to watchOS Info.plist
- [ ] Build and run on physical iPhone
- [ ] Install Watch app on paired Apple Watch
- [ ] Start workout on iPhone
- [ ] Start HealthKit tracking on Watch
- [ ] Verify metrics appear on iPhone
- [ ] Check metrics update in real-time

### 🎨 UI Preview

When workout is active on iPhone, you'll see:

```
┌─────────────────────────────┐
│   🍎 Apple Watch Metrics    │
├─────────────┬───────────────┤
│   ❤️ 145    │   🔥 87      │
│    BPM      │    kcal       │
│ Heart Rate  │  Calories     │
├─────────────┴───────────────┤
│ 🟢 Watch workout active     │
└─────────────────────────────┘
```

### 💡 Key Classes & Properties

**WorkoutConnectivityManager (iOS):**
```swift
@Published var heartRate: Double = 0
@Published var activeCalories: Double = 0
@Published var isWatchWorkoutActive = false
@Published var isWatchConnected = false
```

**WorkoutSessionManager (watchOS):**
```swift
@Published var isWorkoutActive = false
@Published var heartRate: Double = 0
@Published var activeCalories: Double = 0
```

### 🐛 Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| No metrics showing | Verify HealthKit capability added to both targets |
| Watch not connecting | Check WatchConnectivity session is activated |
| Data not updating | Ensure Watch workout session is started |
| Privacy errors | Add NSHealthShareUsageDescription to Info.plist |
| Build errors | Check file target memberships (iOS vs watchOS) |

### 📱 Minimum Requirements

- **iOS**: 16.0+
- **watchOS**: 9.0+
- **Xcode**: 14.0+
- **Hardware**: Physical iPhone and Apple Watch (for testing)
- **Pairing**: Watch must be paired with iPhone

---

**Quick Start:**
1. Add HealthKit capabilities
2. Add privacy descriptions
3. Build & run on devices
4. Start workout on iPhone
5. Watch metrics appear automatically! 🎉
