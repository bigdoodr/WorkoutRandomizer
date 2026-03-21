# HealthKit Integration Architecture Diagram

## System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                           iPhone App (iOS)                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌───────────────────────────────────────────────────────────┐    │
│  │              WorkoutPlayerView (SwiftUI)                  │    │
│  │                                                           │    │
│  │  - Exercise name & timer                                 │    │
│  │  - Video player                                          │    │
│  │  - Control buttons                                       │    │
│  │                                                           │    │
│  │  ┌─────────────────────────────────────────────────┐    │    │
│  │  │      HealthMetricsView (if Watch connected)     │    │    │
│  │  │                                                 │    │    │
│  │  │   🍎 Apple Watch Metrics                       │    │    │
│  │  │  ┌──────────────┬─────────────┐                │    │    │
│  │  │  │   ❤️ 145     │   🔥 87     │                │    │    │
│  │  │  │    BPM       │    kcal     │                │    │    │
│  │  │  └──────────────┴─────────────┘                │    │    │
│  │  │   🟢 Watch workout active                      │    │    │
│  │  └─────────────────────────────────────────────────┘    │    │
│  └───────────────────────────────────────────────────────────┘    │
│                              ▲                                     │
│                              │ Observes                            │
│                              │                                     │
│  ┌───────────────────────────┴───────────────────────────────┐    │
│  │       WorkoutConnectivityManager (@MainActor)             │    │
│  │                                                           │    │
│  │  @Published var heartRate: Double                        │    │
│  │  @Published var activeCalories: Double                   │    │
│  │  @Published var isWatchWorkoutActive: Bool               │    │
│  │  @Published var isWatchConnected: Bool                   │    │
│  │                                                           │    │
│  │  func sendWorkoutState()      ──────────────┐            │    │
│  │  func sendTimerUpdate()                     │            │    │
│  │  func sendFeedbackEvent()                   │            │    │
│  │  func sendControlMessage()                  │            │    │
│  │                              ▲               │            │    │
│  └──────────────────────────────┼───────────────┼────────────┘    │
│                                 │               │                 │
│                                 │ Updates       │ Sends           │
│                                 │               ▼                 │
│  ┌──────────────────────────────┴───────────────────────────┐    │
│  │          WatchConnectivityDelegate (nonisolated)         │    │
│  │                                                           │    │
│  │  - Receives messages from Watch                          │    │
│  │  - Decodes WatchHealthMetrics                            │    │
│  │  - Updates WorkoutConnectivityManager                    │    │
│  └───────────────────────────────────────────────────────────┘    │
│                                 ▲                                 │
└─────────────────────────────────┼─────────────────────────────────┘
                                  │
                                  │ WatchConnectivity
                                  │ (Bluetooth & WiFi)
                                  │
┌─────────────────────────────────┼─────────────────────────────────┐
│                                 ▼                                 │
│                     Apple Watch App (watchOS)                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌───────────────────────────────────────────────────────────┐    │
│  │         WorkoutConnectivityManager (Watch Side)           │    │
│  │                                                           │    │
│  │  - Receives workout state from iPhone                    │    │
│  │  - Displays current exercise & timer                     │    │
│  │  - Triggers haptic feedback                              │    │
│  │                              │                            │    │
│  └──────────────────────────────┼────────────────────────────┘    │
│                                 │ Prompts user                    │
│                                 ▼                                 │
│  ┌───────────────────────────────────────────────────────────┐    │
│  │           WorkoutSessionManager (Singleton)               │    │
│  │                                                           │    │
│  │  @Published var heartRate: Double                        │    │
│  │  @Published var activeCalories: Double                   │    │
│  │  @Published var isWorkoutActive: Bool                    │    │
│  │                                                           │    │
│  │  func startWorkout()  ──────────┐                        │    │
│  │  func pauseWorkout()            │                        │    │
│  │  func resumeWorkout()           │                        │    │
│  │  func endWorkout()              │                        │    │
│  │                                 ▼                        │    │
│  └─────────────────────────────────┼──────────────────────────┘    │
│                                    │                              │
│                                    │ Creates &                    │
│                                    │ Manages                      │
│                                    ▼                              │
│  ┌───────────────────────────────────────────────────────────┐    │
│  │              HealthKit Framework (watchOS)                │    │
│  │                                                           │    │
│  │  - HKWorkoutSession                                      │    │
│  │  - HKLiveWorkoutBuilder                                  │    │
│  │  - Collects heart rate from Watch sensors               │    │
│  │  - Calculates active energy burned                       │    │
│  │                              │                            │    │
│  └──────────────────────────────┼────────────────────────────┘    │
│                                 │                                 │
│                                 │ didCollectDataOf                │
│                                 ▼                                 │
│  ┌───────────────────────────────────────────────────────────┐    │
│  │    WorkoutSessionManager.sendHealthMetricsToPhone()       │    │
│  │                                                           │    │
│  │  Creates WatchHealthMetrics:                             │    │
│  │    - heartRate: Double                                   │    │
│  │    - activeCalories: Double                              │    │
│  │    - isWorkoutActive: Bool                               │    │
│  │                                                           │    │
│  │  Sends via WatchConnectivity ────────────────────┐        │    │
│  └──────────────────────────────────────────────────┼────────┘    │
│                                                     │             │
└─────────────────────────────────────────────────────┼─────────────┘
                                                      │
                        ┌─────────────────────────────┘
                        │
                    Back to iPhone
                   (Loop continues
                   every 3-5 seconds)
```

---

## Data Flow Sequence

### 1. Workout Start

```
iPhone                          Watch
  │                              │
  ├─ User taps "Start"           │
  │                              │
  ├─ sendWorkoutState() ────────>│
  │                              │
  ├─ launchWatchApp() ──────────>│
  │                              │
  │                              ├─ Receives workout state
  │                              │
  │                              ├─ Prompts user to start tracking
  │                              │
  │                              ├─ User taps to start
  │                              │
  │                              ├─ WorkoutSessionManager.startWorkout()
  │                              │
  │                              ├─ Creates HKWorkoutSession
  │                              │
  │                              └─ Begins collecting HealthKit data
```

### 2. Real-Time Metrics Updates

```
Watch                                           iPhone
  │                                              │
  ├─ HealthKit collects heart rate              │
  │                                              │
  ├─ workoutBuilder(didCollectDataOf:)          │
  │                                              │
  ├─ Updates local @Published properties        │
  │                                              │
  ├─ sendHealthMetricsToPhone()                 │
  │                                              │
  ├─ Encodes WatchHealthMetrics                 │
  │                                              │
  ├─ WatchConnectivity.sendMessage() ──────────>│
  │                                              │
  │                              WatchConnectivityDelegate
  │                              receives message
  │                                              │
  │                              Decodes metrics │
  │                                              │
  │                              Updates @Published
  │                              properties      │
  │                                              │
  │                              HealthMetricsView
  │                              auto-refreshes  │
  │                                              │
  │<────── (3-5 seconds later, repeat) ─────────┤
```

### 3. Workout Control

```
iPhone                          Watch
  │                              │
  ├─ User taps "Pause"           │
  │                              │
  ├─ sendControlMessage(.paused) >│
  │                              │
  │                              ├─ WorkoutSessionManager.pauseWorkout()
  │                              │
  │                              ├─ HKWorkoutSession.pause()
  │                              │
  │                              └─ Metrics collection pauses
  │                              │
  ├─ User taps "Resume"          │
  │                              │
  ├─ sendControlMessage(.resumed)>│
  │                              │
  │                              ├─ WorkoutSessionManager.resumeWorkout()
  │                              │
  │                              ├─ HKWorkoutSession.resume()
  │                              │
  │                              └─ Metrics collection resumes
```

### 4. Workout End

```
iPhone                          Watch
  │                              │
  ├─ Workout completes           │
  │                              │
  ├─ sendControlMessage(.stopped)>│
  │                              │
  │                              ├─ WorkoutSessionManager.endWorkout()
  │                              │
  │                              ├─ HKWorkoutSession.end()
  │                              │
  │                              ├─ Finalizes workout data
  │                              │
  │                              ├─ Saves to HealthKit
  │                              │
  │                              └─ Resets to initial state
  │                              │
  │<──── Last metrics update ────┤
  │                              │
  ├─ Clears HealthMetricsView    │
  │                              │
  └─ Returns to workout list     │
```

---

## Message Types & Payloads

### iPhone → Watch

**Workout State**
```swift
{
    "type": "workoutState",
    "payload": Data // Encoded WorkoutState
}

struct WorkoutState {
    currentExerciseName: String
    currentIndex: Int
    totalExercises: Int
    timeRemaining: Int
    isRest: Bool
    nextExerciseName: String?
    isPlaying: Bool
    isPaused: Bool
}
```

**Timer Update**
```swift
{
    "type": "timerUpdate",
    "timeRemaining": Int
}
```

**Feedback Event**
```swift
{
    "type": "feedback",
    "event": String // "start", "warning", "end", "complete"
}
```

**Control Message**
```swift
{
    "type": "control",
    "message": String // "workoutPaused", "workoutResumed", "workoutStopped"
}
```

### Watch → iPhone

**Health Metrics**
```swift
{
    "type": "healthMetrics",
    "payload": Data // Encoded WatchHealthMetrics
}

struct WatchHealthMetrics {
    heartRate: Double        // BPM
    activeCalories: Double   // kcal
    isWorkoutActive: Bool
}
```

---

## Class Relationships

```
iOS App:
┌────────────────────────────────────────────┐
│       WorkoutPlayerView                    │
│  (Displays UI, manages workout flow)       │
└──────────────┬─────────────────────────────┘
               │ @StateObject
               ▼
┌────────────────────────────────────────────┐
│   WorkoutConnectivityManager               │
│  (Sends state, receives metrics)           │
│  @MainActor, ObservableObject              │
└──────────────┬─────────────────────────────┘
               │ Delegate
               ▼
┌────────────────────────────────────────────┐
│   WatchConnectivityDelegate                │
│  (Handles WCSession callbacks)             │
│  nonisolated, WCSessionDelegate            │
└────────────────────────────────────────────┘

┌────────────────────────────────────────────┐
│       HealthMetricsView                    │
│  (Displays heart rate & calories)          │
└──────────────┬─────────────────────────────┘
               │ @ObservedObject
               ▼
      WorkoutConnectivityManager
         (same instance)


watchOS App:
┌────────────────────────────────────────────┐
│   WorkoutConnectivityManager (Watch)       │
│  (Receives state from iPhone)              │
└────────────────────────────────────────────┘

┌────────────────────────────────────────────┐
│       WorkoutSessionManager                │
│  (Manages HealthKit workout session)       │
│  Singleton, ObservableObject               │
└──────────────┬─────────────────────────────┘
               │ Manages
               ▼
┌────────────────────────────────────────────┐
│         HKWorkoutSession                   │
│    HKLiveWorkoutBuilder                    │
│  (Apple's HealthKit framework)             │
└────────────────────────────────────────────┘
```

---

## Key Design Patterns

### 1. Observer Pattern
- SwiftUI views observe `@Published` properties
- Automatic UI updates when data changes
- No manual view refresh needed

### 2. Singleton Pattern
- `WorkoutConnectivityManager.shared` (both platforms)
- `WorkoutSessionManager.shared` (watchOS)
- Single source of truth for connectivity and health data

### 3. Delegate Pattern
- `WCSessionDelegate` for WatchConnectivity callbacks
- Separates concurrency concerns (nonisolated delegate)

### 4. Actor Isolation
- `@MainActor` on ObservableObject classes
- Thread-safe UI updates
- Swift Concurrency best practices

### 5. Messaging Pattern
- Dictionary-based messages with "type" key
- JSON encoding for complex data structures
- Reliable delivery via WatchConnectivity

---

## Performance Considerations

### Update Frequency
- HealthKit: ~3-5 seconds (system controlled)
- Timer: Every 1 second
- UI: Automatic SwiftUI refresh on @Published changes

### Network Efficiency
- Only send data when values change
- Use sendMessage() for real-time data
- Use updateApplicationContext() for persistent state

### Battery Impact
- HealthKit workout sessions optimized by Apple
- WatchConnectivity uses efficient Bluetooth/WiFi
- UI updates only when app is active

---

This architecture ensures:
✅ Real-time health data display  
✅ Efficient communication between devices  
✅ Thread-safe UI updates  
✅ Minimal battery impact  
✅ Reliable message delivery  
✅ Clean separation of concerns  
