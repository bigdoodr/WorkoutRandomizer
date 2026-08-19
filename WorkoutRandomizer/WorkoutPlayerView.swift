//  WorkoutPlayerView.swift
//  Bodyweight WorkoutRandomizer
//
//  The running-workout player: timer loop, video playback, audio/haptic feedback, and the HR intention banner.
//  Extracted from WorkoutRandomizer.swift — no behaviour change.

import SwiftUI
internal import UniformTypeIdentifiers
import Observation
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(AVKit)
import AVKit
#endif
#if canImport(HealthKit)
import HealthKit
#endif
#if os(macOS)
import AppKit
#endif

struct WorkoutPlayerView: View {
    let routine: [Exercise]
    let exerciseDuration: Int
    let restDuration: Int
    let restEvery: Int
    let timerStyle: TimerStyle
    let intention: WorkoutIntention
    var selectedFocusAreas: Set<String> = []
    let blocksConfig: RepeatingBlocksConfig?
    let enableSound_iOS_tv_vision: Bool
    let enableHaptics_iOS_vision: Bool
    let enableSound_macOS: Bool
    var durationOverrides: [Int: Int]? = nil

    static let pyramidIntervals: [(work: Int, rest: Int)] = [
        (30, 30), (40, 40), (50, 50), (50, 50), (40, 40), (30, 30)
    ]

    @State private var currentIndex = 0
    @State private var timeRemaining = 0
    @State private var isPlaying = false
    @State private var isPaused = false
    @State private var timer: Timer?
    /// Non-nil while the auto-start countdown ("Get Ready… 3-2-1") is showing
    @State private var startCountdown: Int? = nil

    // Workout stats
    @State private var totalExerciseTime = 0
    @State private var totalRestTime = 0
    @State private var completedExerciseNames: [String] = []
    @State private var peakHeartRate: Double = 0
    @State private var heartRateSamples: [Double] = []
    @State private var showingRecap = false
    @State private var showingStopConfirmation = false
    // HR intention banner
    @State private var intentionBanner: IntentionBannerPayload? = nil
    @State private var intentionBannerTask: Task<Void, Never>? = nil
    @State private var lastBannerExerciseTime: Int = -1
    @State private var highIntensityStreakSeconds: Int = 0
    @State private var userMaxHeartRate: Double = 185 // default: age 35
#if canImport(AVFoundation)
    @State private var audioEngine: AVAudioEngine?
    @State private var playerNode: AVAudioPlayerNode?
#endif
    @StateObject private var videoManager = VideoManager.shared
    @StateObject private var connectivityManager = WorkoutConnectivityManager.shared
    @State private var avPlayer: AVPlayer? = nil
    @State private var playerEndObserver: Any? = nil
    @Environment(\.dismiss) private var dismiss
    
    var currentExercise: Exercise? {
        guard currentIndex < routine.count else { return nil }
        return routine[currentIndex]
    }
    
    var isRest: Bool {
        currentExercise?.name == "Rest"
    }
    
    var videoURL: URL? {
        guard let exercise = currentExercise else { return nil }
        // Prefer the exercise's explicit videoPath (works for left/right expanded variants
        // whose names don't appear as keys in the catalog). Fall back to name lookup only
        // when videoPath is nil (e.g. custom exercises added by the user).
        if let path = exercise.videoPath {
            return videoManager.playableURL(forRelativePath: path)
        }
        return videoManager.url(for: exercise.name)
    }
    
    var nextUpText: String {
        let nextIndex = currentIndex + 1
        if nextIndex >= routine.count {
            return "End of routine"
        }
        let nextExercise = routine[nextIndex]
        if nextExercise.name == "Rest" {
            return "Rest"
        } else {
            return nextExercise.name
        }
    }

    private var currentPyramidPhase: Int {
        guard timerStyle == .pyramid else { return 0 }
        let workBefore = routine[0..<min(currentIndex, routine.count)].filter { $0.name != "Rest" }.count
        let phase = isRest ? max(0, workBefore - 1) : workBefore
        return phase % Self.pyramidIntervals.count
    }

    private var durationForCurrentPosition: Int {
        guard let exercise = currentExercise else { return 0 }
        // Per-exercise override takes highest priority
        if let override = durationOverrides?[currentIndex] { return override }
        if timerStyle == .pyramid {
            let interval = Self.pyramidIntervals[currentPyramidPhase]
            return exercise.name == "Rest" ? interval.rest : interval.work
        }
        if timerStyle == .blocks, let config = blocksConfig {
            let workBefore = routine[0..<min(currentIndex, routine.count)].filter { $0.name != "Rest" }.count
            let exercisePos = isRest ? max(0, workBefore - 1) : workBefore
            let superSetSize = config.blockDurations.count * config.exercisesPerBlock
            let posInSuperSet = exercisePos % max(1, superSetSize)
            let blockIdx = min(posInSuperSet / max(1, config.exercisesPerBlock), config.blockDurations.count - 1)
            return config.blockDurations[blockIdx]
        }
        return exercise.name == "Rest" ? restDuration : exerciseDuration
    }

    private var averageHeartRate: Double {
        heartRateSamples.isEmpty ? 0 : heartRateSamples.reduce(0, +) / Double(heartRateSamples.count)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let isLandscape = proxy.size.width > proxy.size.height
                #if os(iOS)
                let videoMaxH: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 240 : (isLandscape ? 110 : 180)
                #else
                let videoMaxH: CGFloat = 220
                #endif
                let videoHeight = min(proxy.size.height * 0.35, videoMaxH)
                ScrollView {
                    VStack(spacing: 16) {
                        // Video
                        if VideoMode(rawValue: videoManager.videoMode) != Optional.none {
                            if let player = avPlayer {
                                #if os(macOS)
                                AVPlayerLayerView(player: player)
                                    .frame(height: videoHeight)
                                    .cornerRadius(10)
                                #else
                                VideoPlayer(player: player)
                                    .frame(height: videoHeight)
                                    .cornerRadius(10)
                                #endif
                            } else if videoURL != nil {
                                Rectangle()
                                    .fill(Color.black.opacity(0.1))
                                    .frame(height: videoHeight)
                                    .cornerRadius(10)
                            } else if !isRest {
                                // Exercise has no video — show a subtle placeholder
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.gray.opacity(0.08))
                                    VStack(spacing: 6) {
                                        Image(systemName: "video.slash")
                                            .font(.title)
                                            .foregroundStyle(.secondary)
                                        Text("No Video Available")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(height: videoHeight)
                            }
                        }

                        // Exercise Name
                        Text(currentExercise?.name ?? "Workout Complete")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)

                        // Timer
                        Text(timeRemaining > 0 ? "\(timeRemaining)" : "00")
                            .font(.system(size: 64, weight: .bold, design: .monospaced))
                            .foregroundStyle(timeRemaining <= 3 && timeRemaining > 0 ? .red : .primary)

                        // Progress and Next up combined
                        VStack(spacing: 4) {
                            if currentIndex < routine.count {
                                Text("Exercise \(currentIndex + 1) of \(routine.count)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if isPlaying && currentIndex < routine.count {
                                HStack(spacing: 4) {
                                    Text("Next:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(nextUpText)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(nextUpText == "Rest" ? .blue : (nextUpText == "End of routine" ? .green : .primary))
                                }
                            }
                        }
                        
                        // Live workout stats (exercise time, HR zone, nutrient burn)
                        if isPlaying {
                            #if os(iOS)
                            WorkoutLiveStatsView(
                                exerciseTime: totalExerciseTime,
                                heartRate: connectivityManager.heartRate,
                                hasWatchData: connectivityManager.isWatchConnected && connectivityManager.heartRate > 0,
                                intention: intention,
                                maxHeartRate: userMaxHeartRate,
                                zoneThresholds: connectivityManager.watchZoneThresholds
                            )
                            .padding(.top, 4)
                            #else
                            WorkoutLiveStatsView(exerciseTime: totalExerciseTime, heartRate: 0, hasWatchData: false, intention: intention, maxHeartRate: 185)
                                .padding(.top, 4)
                            #endif
                        }

                        // Apple Watch full metrics panel
                        #if os(iOS)
                        if isPlaying && connectivityManager.isWatchConnected {
                            HealthMetricsView(connectivityManager: connectivityManager)
                                .padding(.top, 4)
                        }
                        #endif

                        // Pyramid level indicator — shows the duration actually being counted
                        // down (durationForCurrentPosition), so a custom timer override for
                        // this exercise is reflected here instead of the un-overridden phase value.
                        if timerStyle == .pyramid && isPlaying {
                            let phase = currentPyramidPhase
                            Text("Pyramid \(phase + 1) of \(WorkoutPlayerView.pyramidIntervals.count)  •  \(durationForCurrentPosition)s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Blocks progress indicator — same rationale as above: use the
                        // override-aware duration rather than the raw block config value.
                        if timerStyle == .blocks && isPlaying, let config = blocksConfig {
                            let workBefore = routine[0..<min(currentIndex, routine.count)].filter { $0.name != "Rest" }.count
                            let exercisePos = isRest ? max(0, workBefore - 1) : workBefore
                            let superSetSize = config.blockDurations.count * config.exercisesPerBlock
                            let posInSuperSet = exercisePos % max(1, superSetSize)
                            let blockIdx = min(posInSuperSet / max(1, config.exercisesPerBlock), config.blockDurations.count - 1)
                            let setNum = exercisePos / max(1, superSetSize) + 1
                            Text("Block \(blockIdx + 1) of \(config.blockDurations.count)  •  Set \(setNum)  •  \(durationForCurrentPosition)s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding()
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 6) {
#if os(iOS)
                    if !isPlaying {
                        let watchMsg: String = {
                            if connectivityManager.isWatchReachable { return "You can also start from your Apple Watch" }
                            if connectivityManager.isWatchConnected { return "Watch Connected" }
                            return "Looking for Watch…"
                        }()
                        Label(watchMsg, systemImage: "applewatch")
                            .font(.caption)
                            .foregroundStyle(connectivityManager.isWatchReachable ? .secondary : .tertiary)
                    }
#endif
                    HStack(spacing: 40) {
                        if !isPlaying {
                            Button {
                                startWorkout()
                            } label: {
                                VStack {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 30))
                                    Text("Start")
                                        .font(.caption)
                                }
                                .frame(width: 80, height: 80)
                                .background(.green)
                                .foregroundStyle(.white)
                                .clipShape(Circle())
                            }
                        } else {
                            Button {
                                togglePause()
                            } label: {
                                VStack {
                                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                        .font(.system(size: 30))
                                    Text(isPaused ? "Resume" : "Pause")
                                        .font(.caption)
                                }
                                .frame(width: 80, height: 80)
                                .background(.blue)
                                .foregroundStyle(.white)
                                .clipShape(Circle())
                            }

                            Button {
                                skipExercise()
                            } label: {
                                VStack {
                                    Image(systemName: "forward.fill")
                                        .font(.system(size: 30))
                                    Text("Skip")
                                        .font(.caption)
                                }
                                .frame(width: 80, height: 80)
                                .background(.orange)
                                .foregroundStyle(.white)
                                .clipShape(Circle())
                            }
                        }
                    }
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
                    .shadow(radius: 2)
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Workout")
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
#if os(iOS) || os(visionOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Stop", role: .destructive) {
                        showingStopConfirmation = true
                    }
                }
#else
                ToolbarItem {
                    Button("Stop", role: .destructive) {
                        showingStopConfirmation = true
                    }
                }
#endif
            }
            .confirmationDialog(
                "Stop this workout?",
                isPresented: $showingStopConfirmation,
                titleVisibility: .visible
            ) {
                Button("Stop Workout", role: .destructive) {
                    stopWorkout()
                    dismiss()
                }
                Button("Keep Going", role: .cancel) { }
            } message: {
                Text("Your progress won't be saved to the recap.")
            }
            .overlay(alignment: .top) {
                if let banner = intentionBanner {
                    IntentionBannerView(payload: banner, intentionColor: intention.bannerColor)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .scale(scale: 0.7, anchor: .top)).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                        .padding(.top, 8)
                        .padding(.horizontal, 16)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.58), value: intentionBanner)
#if os(macOS)
            .frame(minWidth: 800, minHeight: 600)
#endif
        }
        .onAppear {
            setupAudio()
            if currentExercise != nil {
                timeRemaining = durationForCurrentPosition
            }
            prepareVideoForCurrentExercise(autoplay: false)
            #if canImport(HealthKit)
            fetchUserMaxHeartRate()
            #endif
            prepareWatchHandoff()
        }
        .onDisappear {
            stopWorkout()
        }
#if os(iOS)
        // The Apple Watch tapped Start — begin after a short countdown
        .onChange(of: connectivityManager.watchRequestedStart) { _, requested in
            if requested {
                connectivityManager.watchRequestedStart = false
                if !isPlaying {
                    beginStartCountdown()
                }
            }
        }
        // The Apple Watch tapped End Workout — stop the routine on the iPhone too
        .onChange(of: connectivityManager.watchRequestedStop) { _, requested in
            if requested {
                connectivityManager.watchRequestedStop = false
                if isPlaying { stopWorkout(); dismiss() }
            }
        }
#endif
        .overlay {
            if let count = startCountdown {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 16) {
                        Text("Get Ready")
                            .font(.title)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                        Text("\(count)")
                            .font(.system(size: 96, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                            .contentTransition(.numericText(countsDown: true))
                        if let name = currentExercise?.name {
                            Text("First up: \(name)")
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingRecap) {
            WorkoutRecapView(
                completedExercises: completedExerciseNames,
                totalExerciseTime: totalExerciseTime,
                totalRestTime: totalRestTime,
                totalCalories: {
                    #if os(iOS)
                    return connectivityManager.activeCalories
                    #else
                    return 0
                    #endif
                }(),
                peakHeartRate: peakHeartRate,
                averageHeartRate: averageHeartRate,
                hrZoneDurations: {
                    #if os(iOS)
                    return connectivityManager.completedZoneDurations
                    #else
                    return []
                    #endif
                }(),
                intention: intention,
                onDismiss: {
                    showingRecap = false
                    dismiss()
                }
            )
        }
    }

    private func prepareVideoForCurrentExercise(autoplay: Bool) {
        // Clear any previous end observer
        if let obs = playerEndObserver {
            NotificationCenter.default.removeObserver(obs)
            playerEndObserver = nil
        }
        guard let url = videoURL, !isRest else {
            // No video for rest or when mode is none
            avPlayer?.pause()
            avPlayer = nil
            return
        }

        // Create the AVPlayerItem off the main thread to avoid blocking gestures/UI
        DispatchQueue.global(qos: .userInitiated).async {
            let item = AVPlayerItem(url: url)

            // Hop back to main to bind to the player and UI-related observers
            DispatchQueue.main.async {
                let player = self.avPlayer ?? AVPlayer()
                player.isMuted = true
                player.replaceCurrentItem(with: item)
                player.actionAtItemEnd = .none

                // Loop when the item ends
                self.playerEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
                    player.seek(to: .zero)
                    player.play()
                }

                self.avPlayer = player
                if autoplay { player.play() }
            }
        }
    }
    
    private func setupAudio() {
#if canImport(AVFoundation)
    #if os(iOS) || os(tvOS) || os(visionOS)
        if audioEngine == nil {
            let engine = AVAudioEngine()
            // Use the engine's output format to ensure channel counts match
            let output = engine.outputNode
            let hwFormat = output.outputFormat(forBus: 0)
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: hwFormat)
            engine.connect(engine.mainMixerNode, to: output, format: hwFormat)
            engine.mainMixerNode.outputVolume = 1.0
            engine.mainMixerNode.volume = 1.0
            audioEngine = engine
            playerNode = node
            do {
                try engine.start()
            } catch {
                // Ignore errors; we'll retry on first feedback
            }
        }
    #endif
#endif
    }
    
    private func playFeedback(_ event: FeedbackEvent) {
        triggerHaptic(for: event)
        sendFeedbackToWatch(event)
#if os(macOS)
        if enableSound_macOS {
            // Use system beep variations by repeating quickly to differentiate
            switch event {
            case .start:
                NSSound.beep()
            case .warning:
                NSSound.beep(); NSSound.beep()
            case .end:
                NSSound.beep(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { NSSound.beep() }
            case .complete:
                // Triple-beep pattern to indicate completion
                NSSound.beep()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSSound.beep() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { NSSound.beep() }
            }
        }
        return
#endif
#if canImport(AVFoundation)
    #if os(iOS) || os(tvOS) || os(visionOS)
        guard enableSound_iOS_tv_vision else { return }
        // Ensure session and engine are ready (configure off-main to avoid blocking gesture)
        DispatchQueue.global(qos: .utility).async {
            let audioSession = AVAudioSession.sharedInstance()
            _ = try? audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            _ = try? audioSession.setActive(true, options: [])
        }

        if audioEngine == nil || playerNode == nil { setupAudio() }
        guard let engine = audioEngine else { return }

        // Offload buffer synthesis and scheduling off the main thread
        DispatchQueue.global(qos: .userInitiated).async {
            let node: AVAudioPlayerNode
            if let existing = self.playerNode { node = existing } else {
                let newNode = AVAudioPlayerNode()
                engine.attach(newNode)
                engine.connect(newNode, to: engine.mainMixerNode, format: nil)
                self.playerNode = newNode
                node = newNode
            }

            if !engine.isRunning { try? engine.start() }
            engine.mainMixerNode.outputVolume = 1.0
            engine.mainMixerNode.volume = 1.0

            let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
            let sampleRate = mixerFormat.sampleRate

            func makeBuffer(freq: Double, dur: Double, bright: Bool = false, gain: Double = 0.8) -> AVAudioPCMBuffer? {
                let frames = AVAudioFrameCount(sampleRate * dur)
                guard let buf = AVAudioPCMBuffer(pcmFormat: mixerFormat, frameCapacity: frames) else { return nil }
                buf.frameLength = frames

                let attack = Int(0.005 * sampleRate)
                let decay = Int(0.06 * sampleRate)
                let sustainLevel = 0.7
                let total = Int(frames)

                let channelCount = Int(mixerFormat.channelCount)
                for ch in 0..<channelCount {
                    if let data = buf.floatChannelData?[ch] {
                        for i in 0..<total {
                            let t = Double(i) / sampleRate
                            let phase = 2.0 * Double.pi * freq * t
                            let raw: Double
                            if bright {
                                let s = sin(phase)
                                raw = 0.8 * (s >= 0 ? 1.0 : -1.0) + 0.2 * s
                            } else {
                                raw = sin(phase)
                            }
                            let amp: Double
                            if i < attack {
                                amp = Double(i) / Double(max(1, attack))
                            } else if i < attack + decay {
                                let d = Double(i - attack) / Double(max(1, decay))
                                amp = 1.0 - (1.0 - sustainLevel) * d
                            } else {
                                amp = sustainLevel
                            }
                            data[i] = Float(raw * amp * gain)
                        }
                    }
                }
                return buf
            }

            let (frequency, duration, bright, gain): (Double, Double, Bool, Double)
            switch event {
            case .start:    (frequency, duration, bright, gain) = (880, 0.12, false, 0.9)
            case .warning:  (frequency, duration, bright, gain) = (1400, 0.10, true, 1.0)
            case .end:      (frequency, duration, bright, gain) = (523.25, 0.22, false, 0.95)
            case .complete: (frequency, duration, bright, gain) = (659.25, 0.18, true, 1.0)
            }

            // Prepare buffers off-main
            var buffers: [AVAudioPCMBuffer] = []
            switch event {
            case .complete:
                let freqs = [frequency, frequency * 1.2, frequency * 1.5]
                for f in freqs {
                    if let buf = makeBuffer(freq: f, dur: 0.16, bright: true, gain: 1.0) {
                        buffers.append(buf)
                    }
                }
            default:
                if let buf = makeBuffer(freq: frequency, dur: duration, bright: bright, gain: gain) {
                    buffers.append(buf)
                }
            }

            // Schedule and play on main to interact with AVAudioEngine safely
            DispatchQueue.main.async {
                for buf in buffers {
                    node.scheduleBuffer(buf, completionHandler: nil)
                }
                if !node.isPlaying { node.play() }
            }
        }
    #endif
#endif
    }
    
    private func triggerHaptic(for event: FeedbackEvent) {
#if os(iOS)
        guard enableHaptics_iOS_vision else { return }
        #if canImport(UIKit)
        let generator: UIFeedbackGenerator
        switch event {
        case .start:
            let g = UIImpactFeedbackGenerator(style: .medium)
            g.prepare(); g.impactOccurred(); generator = g
        case .warning:
            let g = UIImpactFeedbackGenerator(style: .rigid)
            g.prepare(); g.impactOccurred(intensity: 1.0); generator = g
        case .end:
            let g = UINotificationFeedbackGenerator()
            g.prepare(); g.notificationOccurred(.success); generator = g
        case .complete:
            let g = UINotificationFeedbackGenerator()
            g.prepare(); g.notificationOccurred(.success); generator = g
        }
        _ = generator // keep reference in scope
        #endif
#endif
    }
    
    private func sendWorkoutStateToWatch() {
        #if os(iOS)
        let state = WorkoutState(
            currentExerciseName: currentExercise?.name ?? "Complete",
            currentIndex: currentIndex,
            totalExercises: routine.count,
            timeRemaining: timeRemaining,
            isRest: isRest,
            nextExerciseName: currentIndex + 1 < routine.count ? routine[currentIndex + 1].name : nil,
            isPlaying: isPlaying,
            isPaused: isPaused
        )
        connectivityManager.sendWorkoutState(state)
        #endif
    }
    
    private func sendFeedbackToWatch(_ event: FeedbackEvent) {
        #if os(iOS)
        let feedbackType: FeedbackType
        switch event {
        case .start: feedbackType = .start
        case .warning: feedbackType = .warning
        case .end: feedbackType = .end
        case .complete: feedbackType = .complete
        }
        connectivityManager.sendFeedbackEvent(feedbackType)
        #endif
    }
    
    /// Shows a short "Get Ready" countdown, then starts the workout. Used when
    /// the session was initiated from the Apple Watch or the handoff screen.
    private func beginStartCountdown(seconds: Int = 3) {
        guard !isPlaying, startCountdown == nil else { return }
        startCountdown = seconds
        playFeedback(.warning)
        Task { @MainActor in
            var remaining = seconds
            while remaining > 1 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                remaining -= 1
                withAnimation { startCountdown = remaining }
                playFeedback(.warning)
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            withAnimation { startCountdown = nil }
            startWorkout()
        }
    }

    private func startWorkout() {
        // Flip minimal UI state immediately to finish the gesture quickly
        isPlaying = true
        setIdleTimer(disabled: true)

        // Defer heavier work to the next run loop to avoid blocking the gesture handler
        DispatchQueue.main.async {
            self.playFeedback(.start)
            self.prepareVideoForCurrentExercise(autoplay: true)
            self.sendWorkoutStateToWatch()
            self.launchWatchWorkoutSession()
            self.startTimer()
        }
    }

    /// Keeps the screen awake during a workout session (iOS only).
    private func setIdleTimer(disabled: Bool) {
#if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = disabled
#endif
    }

    /// Called when the player appears: auto-launches the watch app (via
    /// startWatchApp) so its Ready screen comes up without the user having to
    /// open it manually, and signals readiness over WatchConnectivity.
    private func prepareWatchHandoff() {
#if os(iOS)
        guard !isPlaying else { return }
        connectivityManager.watchRequestedStart = false
        connectivityManager.sendPrepareToStart()
        launchWatchWorkoutSession()
#endif
    }
    
    #if canImport(HealthKit)
    /// Classifies the session for HealthKit based on which focus areas were selected,
    /// falling back to the chosen intention when the areas don't point at one specific
    /// activity (e.g. a mixed Chest/Legs/Shoulders session).
    private var resolvedActivityType: HKWorkoutActivityType {
        let coreAreas: Set<String> = ["Core", "Core: Strength"]
        let flexibilityAreas: Set<String> = [
            "Morning Stretches", "Evening Recovery", "Cool Down", "Warm-Up: Hips", "Warm-Up: Full Body"
        ]

        if !selectedFocusAreas.isEmpty && selectedFocusAreas.isSubset(of: coreAreas) {
            return .coreTraining
        }
        if !selectedFocusAreas.isEmpty && selectedFocusAreas.isSubset(of: flexibilityAreas) {
            return .flexibility
        }
        switch intention {
        case .strengthPower:
            return .functionalStrengthTraining
        case .generalFitness, .fatBurn, .cardioEndurance:
            return .highIntensityIntervalTraining
        }
    }
    #endif

    private func launchWatchWorkoutSession() {
        #if os(iOS)
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = resolvedActivityType
        configuration.locationType = .indoor
        store.startWatchApp(with: configuration) { success, error in
            if let error = error {
                print("Failed to launch watch app: \(error.localizedDescription)")
            } else if success {
                print("Watch app launched for workout session")
            }
        }
        #endif
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard !isPaused else { return }

            timeRemaining -= 1

            // Track exercise vs rest time
            if isRest {
                totalRestTime += 1
            } else {
                totalExerciseTime += 1
            }

            // Sample heart rate for recap stats + send timer update to watch every second.
            // Both touch the MainActor-isolated connectivityManager, so they're hopped
            // together in one Task to avoid referencing its main-actor-isolated
            // properties from the Sendable Timer closure directly.
            #if os(iOS)
            let currentTime = timeRemaining
            let currentExerciseTime = totalExerciseTime
            Task { @MainActor in
                let hr = connectivityManager.heartRate
                if hr > 0 {
                    heartRateSamples.append(hr)
                    if hr > peakHeartRate { peakHeartRate = hr }
                    // Check HR/intention alignment every 30 seconds during exercise
                    if !isRest && currentExerciseTime > 0
                        && currentExerciseTime % 30 == 0
                        && currentExerciseTime != lastBannerExerciseTime {
                        lastBannerExerciseTime = currentExerciseTime
                        let zone = hrZoneName(bpm: hr, maxHR: userMaxHeartRate)
                        if zone == "Zone 4" || zone == "Zone 5" {
                            highIntensityStreakSeconds += 30
                        } else {
                            highIntensityStreakSeconds = 0
                        }
                        showIntentionBannerIfNeeded(hr: hr)
                    }
                }
                connectivityManager.sendTimerUpdate(timeRemaining: currentTime)
            }
            #endif

            if timeRemaining == 3 {
                playFeedback(.warning)
            }

            if timeRemaining <= 0 {
                playFeedback(.end)
                nextExercise()
            }
        }
    }
    
    private func nextExercise() {
        // Record the completed exercise before advancing
        if let ex = currentExercise, ex.name != "Rest" {
            completedExerciseNames.append(ex.name)
        }

        currentIndex += 1

        if currentIndex >= routine.count {
            playFeedback(.complete)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                #if os(iOS)
                self.connectivityManager.sendWorkoutCompleted(
                    count: self.completedExerciseNames.count,
                    totalSeconds: self.totalExerciseTime + self.totalRestTime,
                    label: "Workout"
                )
                #endif
                self.stopWorkout()
                self.showingRecap = true
            }
            return
        }

        timeRemaining = durationForCurrentPosition
        prepareVideoForCurrentExercise(autoplay: true)
        playFeedback(.start)
        sendWorkoutStateToWatch()
    }
    
    private func togglePause() {
        isPaused.toggle()
        playFeedback(.warning)
        sendWorkoutStateToWatch()
        #if os(iOS)
        connectivityManager.sendControlMessage(isPaused ? .workoutPaused : .workoutResumed)
        #endif
        if isPaused { avPlayer?.pause() } else { avPlayer?.play() }
    }
    
    private func skipExercise() {
        playFeedback(.warning)
        nextExercise()
    }
    
    private func stopWorkout() {
        setIdleTimer(disabled: false)
        avPlayer?.pause()
        avPlayer = nil
        if let obs = playerEndObserver {
            NotificationCenter.default.removeObserver(obs)
            playerEndObserver = nil
        }
#if canImport(AVFoundation)
        playerNode?.stop()
        audioEngine?.stop()
#endif
        timer?.invalidate()
        timer = nil
        intentionBannerTask?.cancel()
        #if os(iOS)
        connectivityManager.sendControlMessage(.workoutStopped)
        #endif
    }

    #if canImport(HealthKit)
    private func fetchUserMaxHeartRate() {
        let healthStore = HKHealthStore()
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            let components = try healthStore.dateOfBirthComponents()
            if let year = components.year {
                let age = Calendar.current.component(.year, from: Date()) - year
                if age > 10 && age < 120 {
                    userMaxHeartRate = 220.0 - Double(age)
                }
            }
        } catch {
            // Keep the default (assumes age 35)
        }
    }
    #endif

    private func hrZoneName(bpm: Double, maxHR: Double) -> String {
        #if os(iOS)
        let thresholds = connectivityManager.watchZoneThresholds
        if !thresholds.isEmpty {
            let idx = thresholds.firstIndex(where: { bpm < $0 }) ?? thresholds.count
            return "Zone \(idx + 1)"
        }
        #endif
        let pct = bpm / maxHR
        switch pct {
        case ..<0.60:       return "Zone 1"
        case 0.60..<0.70:   return "Zone 2"
        case 0.70..<0.80:   return "Zone 3"
        case 0.80..<0.90:   return "Zone 4"
        default:             return "Zone 5"
        }
    }

    // Zones 4-5 are meant for short bursts (per standard HR zone guidance: Zone 5 is
    // "unsustainable for more than 1-3 minutes", Zone 4 is "only short phases possible").
    // Once a continuous high-intensity streak crosses this, stop cheering the user on
    // and nudge them to recover instead — regardless of intention.
    private let highIntensitySafetyThresholdSeconds = 180

    private func intentionBannerPayload(hr: Double) -> IntentionBannerPayload? {
        let zone = hrZoneName(bpm: hr, maxHR: userMaxHeartRate)

        if (zone == "Zone 4" || zone == "Zone 5")
            && highIntensityStreakSeconds >= highIntensitySafetyThresholdSeconds {
            return IntentionBannerPayload(
                message: "You've been pushing hard for a while — ease back to recover before your next push.",
                icon: "arrow.down.heart.fill",
                tone: .nudgeDown
            )
        }

        switch (intention, zone) {

        // Fat Burn
        case (.fatBurn, "Zone 1"):
            return IntentionBannerPayload(message: "Pick up the pace — your fat-burn zone is just ahead!", icon: "hare.fill", tone: .nudgeUp)
        case (.fatBurn, "Zone 2"), (.fatBurn, "Zone 3"):
            return IntentionBannerPayload(message: "Sweet spot — you're torching fat right now! 🔥", icon: "flame.fill", tone: .positive)
        case (.fatBurn, "Zone 4"), (.fatBurn, "Zone 5"):
            return IntentionBannerPayload(message: "Ease up a little — you're burning carbs, not fat.", icon: "tortoise.fill", tone: .nudgeDown)

        // Cardio Endurance
        case (.cardioEndurance, "Zone 1"):
            return IntentionBannerPayload(message: "Push harder to build your aerobic base!", icon: "arrow.up.circle.fill", tone: .nudgeUp)
        case (.cardioEndurance, "Zone 2") where hr < 110:
            return IntentionBannerPayload(message: "A bit more effort will grow your aerobic capacity!", icon: "arrow.up.circle.fill", tone: .nudgeUp)
        case (.cardioEndurance, "Zone 3"), (.cardioEndurance, "Zone 4"):
            return IntentionBannerPayload(message: "Aerobic engine firing — building real endurance! 💪", icon: "heart.fill", tone: .positive)
        case (.cardioEndurance, "Zone 5"):
            return IntentionBannerPayload(message: "Incredible effort! Your cardiovascular fitness is skyrocketing!", icon: "star.fill", tone: .positive)

        // Strength / Power
        case (.strengthPower, "Zone 1"), (.strengthPower, "Zone 2"):
            return IntentionBannerPayload(message: "Power lives in Zone 4+ — channel that energy!", icon: "arrow.up.circle.fill", tone: .nudgeUp)
        case (.strengthPower, "Zone 3"):
            return IntentionBannerPayload(message: "Getting there — push for that extra burst!", icon: "arrow.up.circle.fill", tone: .nudgeUp)
        case (.strengthPower, "Zone 4"), (.strengthPower, "Zone 5"):
            return IntentionBannerPayload(message: "POWER MODE — you're absolutely CRUSHING it! 💪", icon: "bolt.fill", tone: .positive)

        // General Fitness
        case (.generalFitness, "Zone 1"):
            return IntentionBannerPayload(message: "A little more effort will give your fitness a real boost!", icon: "arrow.up.circle.fill", tone: .nudgeUp)
        case (.generalFitness, "Zone 2"), (.generalFitness, "Zone 3"):
            return IntentionBannerPayload(message: "Perfect pace — you're right where you want to be!", icon: "checkmark.circle.fill", tone: .positive)
        case (.generalFitness, "Zone 4"), (.generalFitness, "Zone 5"):
            return IntentionBannerPayload(message: "You're working hard — keep it up! 🔥", icon: "flame.fill", tone: .positive)

        default:
            return nil
        }
    }

    private func showIntentionBannerIfNeeded(hr: Double) {
        guard let payload = intentionBannerPayload(hr: hr) else { return }
        intentionBannerTask?.cancel()
        withAnimation { intentionBanner = payload }
        intentionBannerTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { intentionBanner = nil }
        }
    }
}

private struct IntentionBannerPayload: Equatable {
    enum Tone: Equatable { case positive, nudgeUp, nudgeDown }
    let message: String
    let icon: String
    let tone: Tone
}

private struct IntentionBannerView: View {
    let payload: IntentionBannerPayload
    let intentionColor: Color

    @State private var appeared = false

    private var displayColor: Color {
        switch payload.tone {
        case .positive: return intentionColor
        case .nudgeUp:  return .orange
        case .nudgeDown: return .teal
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: payload.icon)
                .font(.title3)
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: appeared)
            Text(payload.message)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Capsule().fill(displayColor.gradient))
        .shadow(color: displayColor.opacity(0.45), radius: 10, y: 4)
        .onAppear { appeared = true }
    }
}
