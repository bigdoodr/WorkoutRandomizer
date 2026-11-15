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
    /// Every timing decision in one value: style, durations, block config, the Pyramid ladder
    /// and any Custom Timers overrides.
    ///
    /// These used to arrive as six separate parameters that the player immediately reassembled
    /// into exactly this — which meant the generator and the player each had to remember to
    /// keep six things in step, and adding anything timing-related (the Pyramid ladder was the
    /// last one) meant threading a seventh through both.
    let timing: WorkoutTiming
    let intention: WorkoutIntention
    var selectedFocusAreas: Set<String> = []
    let enableSound_iOS_tv_vision: Bool
    let enableHaptics_iOS_vision: Bool
    let enableSound_macOS: Bool
    /// Routine indices where each ladder round begins. Non-nil only for Add-On styles.
    var ladderRoundStarts: [Int]? = nil

    @State private var currentIndex = 0
    @State private var timeRemaining = 0
    @State private var isPlaying = false
    @State private var isPaused = false
    @State private var timer: Timer?
    /// The routine as a plan and where it stands on the clock. The countdown is *derived* from
    /// these (same `PlanClock` math as the Apple Watch) rather than counted down tick by tick, so
    /// a stalled or late timer can't make this player drift from the Watch.
    @State private var plan: WorkoutPlan?
    @State private var anchor: ClockAnchor?
    /// Non-nil while the auto-start countdown ("Get Ready… 3-2-1") is showing
    @State private var startCountdown: Int? = nil

    // Workout stats
    @State private var totalExerciseTime = 0
    @State private var totalRestTime = 0
    @State private var completedExerciseNames: [String] = []
    @State private var peakHeartRate: Double = 0
    @State private var heartRateSamples: [Double] = []
    @State private var showingRecap = false
    /// Whether the recap goes up full screen (regular width) rather than as a sheet. Latched when
    /// the workout finishes, like the player's own presentation, so a fold change while it's
    /// open can't swap the presentation style out from under it.
    @State private var recapIsFullScreen = false
    @State private var showingStopConfirmation = false
    // HR intention banner
    @State private var intentionBanner: IntentionBannerPayload? = nil
    @State private var intentionBannerTask: Task<Void, Never>? = nil
    @State private var lastBannerExerciseTime: Int = -1
    @State private var highIntensityStreakSeconds: Int = 0
#if canImport(AVFoundation)
    @State private var audioEngine: AVAudioEngine?
    @State private var playerNode: AVAudioPlayerNode?
#endif
    @StateObject private var videoManager = VideoManager.shared
    @StateObject private var connectivityManager = WorkoutConnectivityManager.shared
    @State private var avPlayer: AVPlayer? = nil
    @State private var playerEndObserver: Any? = nil
    @Environment(\.dismiss) private var dismiss
    // Regular width signals an iPad-sized (or iPhone Duo inner-display-sized) layout — this is
    // the recommended way to size up, rather than checking device idiom directly, since it also
    // covers the inner display of a dual-screen iPhone.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var currentExercise: Exercise? {
        guard currentIndex < routine.count else { return nil }
        return routine[currentIndex]
    }
    
    var isRest: Bool {
        currentExercise?.name == "Rest"
    }
    
    var videoURL: URL? { videoURL(for: currentExercise) }

    /// The demo clip for any exercise (the current one, or the next one for the Up Next card).
    func videoURL(for exercise: Exercise?) -> URL? {
        guard let exercise else { return nil }
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

    /// Which ladder round the current slot falls in, one-based, plus the total round count.
    private var currentLadderRound: (round: Int, total: Int)? {
        guard let starts = ladderRoundStarts, !starts.isEmpty else { return nil }
        let round = starts.lastIndex(where: { $0 <= currentIndex }).map { $0 + 1 } ?? 1
        return (round: round, total: starts.count)
    }

    private var currentPyramidPhase: Int {
        timing.pyramidPhase(at: currentIndex, in: routine)
    }

    private var durationForCurrentPosition: Int {
        timing.duration(at: currentIndex, in: routine)
    }

    private var averageHeartRate: Double {
        heartRateSamples.isEmpty ? 0 : heartRateSamples.reduce(0, +) / Double(heartRateSamples.count)
    }

    // MARK: - Layout pieces
    // Split out of `body` so the same pieces can sit in one column (portrait, compact) or in two
    // (landscape on a regular-width display such as the Duo's inner screen).

    /// The live Watch numbers for the overlay — present only while a Watch workout is running.
    private var liveSnapshot: LiveMetricsSnapshot? {
        #if os(iOS)
        guard connectivityManager.hasLiveWatchSession else { return nil }
        return LiveMetricsSnapshot(
            heartRate: connectivityManager.heartRate,
            zone: ZoneResolver.resolve(heartRate: connectivityManager.heartRate,
                                       watchZoneIndex: connectivityManager.watchZoneIndex,
                                       liveThresholds: connectivityManager.watchZoneThresholds),
            calories: connectivityManager.activeCalories,
            elapsedSeconds: totalExerciseTime + totalRestTime
        )
        #else
        return nil
        #endif
    }

    /// The one-line "Up Next: …" used where there isn't room for the card.
    private func upNextLine(scale: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text("Up Next:")
                .font(.system(size: 15 * scale))
                .foregroundStyle(.secondary)
            Text(nextUpText)
                .font(.system(size: 15 * scale, weight: .semibold))
                .foregroundStyle(nextUpText == "Rest" ? .blue : (nextUpText == "End of routine" ? .green : .primary))
        }
    }

    /// The next real exercise after the current slot (skipping rests), with a note when a rest
    /// comes first. Nil at the end of the routine.
    private var nextExerciseInfo: (exercise: Exercise, note: String?)? {
        let start = currentIndex + 1
        guard start < routine.count else { return nil }
        // A rest between here and the next exercise is worth a mention ("after a 10s rest").
        let note: String? = routine[start].name == "Rest"
            ? "after a \(timing.duration(at: start, in: routine))s rest" : nil
        for index in start..<routine.count where routine[index].name != "Rest" {
            return (routine[index], note)
        }
        return nil
    }

    /// Which exercise owns each slot (nil for a rest), for the exercises-only count.
    private var exerciseOwners: [Int?] {
        routine.indices.map { routine[$0].name == "Rest" ? nil : $0 }
    }

    /// The "N of M" shown under the video: exercises only. On a rest it points at the next one.
    private var exerciseProgress: (number: Int, total: Int) {
        let numbering = ExerciseNumbering.ordinals(for: exerciseOwners)
        guard numbering.ordinals.indices.contains(currentIndex) else { return (numbering.total, numbering.total) }
        return (numbering.ordinals[currentIndex], numbering.total)
    }

    /// 0...1 through the current slot, for the thin progress bar.
    private var slotProgress: Double? {
        guard isPlaying, durationForCurrentPosition > 0 else { return nil }
        return Double(timeRemaining) / Double(durationForCurrentPosition)
    }

    /// The video area, Fitness+ style: the demo video with the countdown over it (and, during a
    /// live Watch workout, the heart-rate numbers). On a rest screen, or with video turned off,
    /// the same content is drawn enlarged in the video's place. Always 16:9, full width.
    @ViewBuilder
    private func videoBlock() -> some View {
        let videoOff = VideoMode(rawValue: videoManager.videoMode).map { $0 == .none } ?? false
        if isRest || videoOff {
            PlayerOverlay(countdown: timeRemaining, progress: slotProgress, live: liveSnapshot, style: .panel)
                .aspectRatio(16 / 9, contentMode: .fit)
        } else {
            videoContent
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    PlayerOverlay(countdown: timeRemaining, progress: slotProgress, live: liveSnapshot, style: .corner)
                }
        }
    }

    /// The demo video (or its placeholder), filling whatever space it's given.
    @ViewBuilder
    private var videoContent: some View {
        if let player = avPlayer {
            #if os(macOS)
            AVPlayerLayerView(player: player)
            #else
            VideoPlayer(player: player)
            #endif
        } else if videoURL != nil {
            Rectangle().fill(Color.black.opacity(0.1))
        } else {
            // Exercise has no video — show a subtle placeholder
            ZStack {
                Rectangle().fill(Color.gray.opacity(0.08))
                VStack(spacing: 6) {
                    Image(systemName: "video.slash")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("No Video Available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Under the video: the exercise name, what's up next, and a small N of M. (The countdown and
    /// the live Watch numbers are in the video overlay.) With `roomy` (regular-width layouts) the
    /// text is larger — scaled to the height available — and Up Next becomes a card with a still
    /// from the next exercise's video, plus a thin progress bar with a segment per exercise.
    @ViewBuilder
    private func infoBlock(roomy: Bool, scale: CGFloat) -> some View {
        #if os(iOS)
        if roomy {
            WorkoutSegmentBar(total: exerciseProgress.total, current: exerciseProgress.number - 1)
        }
        #endif

        // Exercise Name
        Text(currentExercise?.name ?? "Workout Complete")
            .font(roomy ? .system(size: 30 * scale, weight: .bold) : .title.weight(.bold))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)

        // Up next
        if isPlaying && currentIndex < routine.count {
            #if os(iOS)
            if roomy, let next = nextExerciseInfo {
                UpNextCard(name: next.exercise.name, note: next.note, videoURL: videoURL(for: next.exercise), scale: scale)
            } else {
                upNextLine(scale: roomy ? scale : 1)
            }
            #else
            upNextLine(scale: 1)
            #endif
        }

        // Small "Exercise N of M" — exercises only; rests don't count
        if currentIndex < routine.count {
            Text("Exercise \(exerciseProgress.number) of \(exerciseProgress.total)")
                .font(roomy ? .system(size: 14 * scale) : .caption)
                .foregroundStyle(.secondary)
        }

        // Apple Watch metrics while a Watch workout is live; a one-line hint otherwise
        #if os(iOS)
        if isPlaying {
            // The video overlay carries the live numbers, so the full panel is dropped; this
            // is just the hint when no Watch workout is running.
            WatchMetricsSection(connectivityManager: connectivityManager, showsPanelWhenLive: false)
                .padding(.top, 4)
        }
        #endif

        // Pyramid level indicator — shows the duration actually being counted
        // down (durationForCurrentPosition), so a custom timer override for
        // this exercise is reflected here instead of the un-overridden phase value.
        if timing.style == .pyramid && isPlaying {
            let phase = currentPyramidPhase
            Text("Pyramid \(phase + 1) of \(timing.pyramidIntervals.count)  •  \(durationForCurrentPosition)s")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        // Blocks progress indicator — same rationale as above: use the
        // override-aware duration rather than the raw block config value.
        if timing.style == .blocks && isPlaying,
           let position = timing.blockPosition(at: currentIndex, in: routine) {
            Text("Block \(position.blockIndex + 1) of \(position.blockCount)  •  Set \(position.setNumber)  •  \(durationForCurrentPosition)s")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        // Ladder progress — without this you cannot tell how far up (or back
        // down) the ladder you are, since the exercises simply repeat.
        if timing.style.isLadder && isPlaying, let ladder = currentLadderRound {
            Text("Round \(ladder.round) of \(ladder.total)  •  \(durationForCurrentPosition)s")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

    }

    /// Start / Pause / Skip, with the Watch status line above Start. Sized by the caller so a short
    /// screen gets a slimmer bar and the content above it keeps its room.
    private func controlsBar(buttonSize: CGFloat, iconSize: CGFloat, verticalPadding: CGFloat) -> some View {

                            VStack(spacing: 6) {
        // The intention nudge lives here, above the controls, so it never covers the video.
        if let banner = intentionBanner {
            IntentionBannerView(payload: banner, intentionColor: intention.bannerColor)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
                .padding(.horizontal, 12)
        }
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
                                                .font(.system(size: iconSize))
                                            Text("Start")
                                                .font(.caption)
                                        }
                                        .frame(width: buttonSize, height: buttonSize)
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
                                                .font(.system(size: iconSize))
                                            Text(isPaused ? "Resume" : "Pause")
                                                .font(.caption)
                                        }
                                        .frame(width: buttonSize, height: buttonSize)
                                        .background(.blue)
                                        .foregroundStyle(.white)
                                        .clipShape(Circle())
                                    }

                                    Button {
                                        skipExercise()
                                    } label: {
                                        VStack {
                                            Image(systemName: "forward.fill")
                                                .font(.system(size: iconSize))
                                            Text("Skip")
                                                .font(.caption)
                                        }
                                        .frame(width: buttonSize, height: buttonSize)
                                        .background(.orange)
                                        .foregroundStyle(.white)
                                        .clipShape(Circle())
                                    }
                                }
                            }
                            }
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
        .shadow(radius: 2)
        .padding(.horizontal)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let isLandscape = proxy.size.width > proxy.size.height
                #if os(iOS)
                let isRegular = horizontalSizeClass == .regular
                #else
                let isRegular = false
                #endif
                // A short, narrow screen — the Duo's outer display, an iPhone SE: controls a size down.
                let isCompactHeight = !isRegular && proxy.size.height < 720
                let sectionSpacing: CGFloat = isCompactHeight ? 8 : 12
                let buttonSize: CGFloat = isCompactHeight ? 64 : 80
                let iconSize: CGFloat = isCompactHeight ? 24 : 30
                let barPadding: CGFloat = isCompactHeight ? 8 : 12
                // Regular width (the Duo's inner display, iPads) has room under the video for larger
                // text, an Up Next card and a progress bar. Phones and the Duo's outer display
                // keep the compact layout.
                #if os(iOS)
                let roomyScale = RoomyMetrics.scale(forHeight: proxy.size.height)
                #else
                let roomyScale: CGFloat = 1
                #endif
                if isRegular && isLandscape {
                    // Two columns: the video takes the wide side, the rest of the player sits
                    // beside it and scrolls on its own if it needs to.
                    let columnWidth = proxy.size.width * 0.58
                    HStack(alignment: .top, spacing: 20) {
                        videoBlock()
                            .frame(width: columnWidth)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        ScrollView {
                            VStack(spacing: sectionSpacing) {
                                infoBlock(roomy: true, scale: roomyScale)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            .padding(.vertical)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .safeAreaInset(edge: .bottom) { controlsBar(buttonSize: buttonSize, iconSize: iconSize, verticalPadding: barPadding) }
                } else {
                    ScrollView {
                        VStack(spacing: sectionSpacing) {
                            // Full width, and as tall as 16:9 allows (capped so a landscape phone
                            // still has room for the controls).
                            videoBlock()
                                .frame(maxHeight: proxy.size.height * (isLandscape ? 0.6 : 0.55))
                            VStack(spacing: isRegular ? sectionSpacing * roomyScale : sectionSpacing) {
                                infoBlock(roomy: isRegular, scale: roomyScale)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .safeAreaInset(edge: .bottom) { controlsBar(buttonSize: buttonSize, iconSize: iconSize, verticalPadding: barPadding) }
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
            Task { await HRZoneSettings.shared.refreshFromHealthKit() }
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
        // The Apple Watch tapped Pause/Resume — mirror it here so both devices agree
        .onChange(of: connectivityManager.watchRequestedPause) { _, requested in
            if requested {
                connectivityManager.watchRequestedPause = false
                if isPlaying { togglePause() }
            }
        }
        // The Apple Watch made a newer clock anchor (its Pause / Resume / Skip) — follow it
        .onChange(of: connectivityManager.incomingWatchAnchor) { _, anchor in
            applyWatchAnchor(anchor)
        }
        // The Apple Watch tapped Skip — advance one slot on the iPhone too
        .onChange(of: connectivityManager.watchRequestedSkip) { _, requested in
            if requested {
                connectivityManager.watchRequestedSkip = false
                if isPlaying { skipExercise() }
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
        .sheet(isPresented: Binding(
            get: { showingRecap && !recapIsFullScreen },
            set: { showingRecap = $0 }
        )) {
            recapView
        }
        #if os(iOS)
        .fullScreenCover(isPresented: Binding(
            get: { showingRecap && recapIsFullScreen },
            set: { showingRecap = $0 }
        )) {
            recapView
        }
        #endif
    }

    private var recapView: some View {
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
                selectedFocusAreas: selectedFocusAreas,
                onDismiss: {
                    // Dismiss the player itself: that takes the recap it presented away in the same
                    // transition. (Clearing `showingRecap` first dismissed the recap alone and let the
                    // finished player show for a moment before it, too, was dismissed.)
                    dismiss()
                }
            )
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
            case .enterActive, .enterCoolDown:
                // Distinct from the routine's own start/end: a single longer beep.
                NSSound.beep()
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
            case .start:        (frequency, duration, bright, gain) = (880, 0.12, false, 0.9)
            case .warning:      (frequency, duration, bright, gain) = (1400, 0.10, true, 1.0)
            case .end:          (frequency, duration, bright, gain) = (523.25, 0.22, false, 0.95)
            case .complete:     (frequency, duration, bright, gain) = (659.25, 0.18, true, 1.0)
            case .enterActive:  (frequency, duration, bright, gain) = (493.88, 0.12, true, 0.95)
            case .enterCoolDown: (frequency, duration, bright, gain) = (659.25, 0.18, false, 0.85)
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
            case .enterActive:
                // Two-note ascending chime — warm-up is over, work begins.
                for f in [frequency, frequency * 1.335] {
                    if let buf = makeBuffer(freq: f, dur: 0.12, bright: true, gain: 0.95) {
                        buffers.append(buf)
                    }
                }
            case .enterCoolDown:
                // Two-note descending chime — settle into the cool-down.
                for f in [frequency, frequency * 0.667] {
                    if let buf = makeBuffer(freq: f, dur: 0.18, bright: false, gain: 0.85) {
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
        case .enterActive:
            let g = UIImpactFeedbackGenerator(style: .heavy)
            g.prepare(); g.impactOccurred(); generator = g
        case .enterCoolDown:
            let g = UIImpactFeedbackGenerator(style: .soft)
            g.prepare(); g.impactOccurred(); generator = g
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
            isPaused: isPaused,
            activityTypeRaw: resolvedActivityType.rawValue
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
        case .enterActive: feedbackType = .enterActive
        case .enterCoolDown: feedbackType = .enterCoolDown
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
            // Stamp the anchor last, immediately before the clock starts, so "slot 0, 0 s in"
            // is the moment the first exercise actually begins here.
            self.beginPlanSync()
            self.startTimer()
        }
    }

    // MARK: - Plan + clock anchor (Apple Watch sync)

    /// Sends the Watch the whole routine and where we are in it, so it can work out the current
    /// exercise from its own clock instead of waiting on a message per transition.
    private func beginPlanSync() {
        let now = Date().timeIntervalSince1970
        // "N of M" counts exercises only, so the Watch (which shows the plan's group numbers)
        // matches this screen.
        let numbering = ExerciseNumbering.ordinals(for: exerciseOwners)
        let slots = routine.indices.map { index in
            PlanSlot(name: routine[index].name,
                     isRest: routine[index].name == "Rest",
                     duration: timing.duration(at: index, in: routine),
                     groupIndex: max(0, numbering.ordinals[index] - 1))
        }
        #if canImport(HealthKit)
        let activityTypeRaw: UInt? = resolvedActivityType.rawValue
        #else
        let activityTypeRaw: UInt? = nil
        #endif
        let newPlan = WorkoutPlan(id: UUID().uuidString, createdAt: now, slots: slots,
                                  activityTypeRaw: activityTypeRaw, groupCount: numbering.total)
        let start = PlanClock.anchor(planID: newPlan.id, slotIndex: currentIndex, secondsIntoSlot: 0,
                                     isRunning: !isPaused, now: now, source: .phone)
        plan = newPlan
        anchor = start
        #if os(iOS)
        connectivityManager.beginPlan(PlanSync(plan: newPlan, anchor: start))
        #endif
    }

    /// How far into the current slot this player is, from what it is showing.
    private var secondsIntoCurrentSlot: Double {
        Double(max(0, durationForCurrentPosition - timeRemaining))
    }

    /// Tells the Watch about the anchor we just made. Called on Pause / Resume / Skip — the
    /// moments the Watch can't work out for itself. (Ordinary transitions need no message: the
    /// Watch derives them from the plan.)
    private func sendPhoneAnchor() {
        #if os(iOS)
        guard let anchor else { return }
        connectivityManager.sendAnchor(anchor)
        #endif
    }

    /// The Watch made a newer anchor (Pause / Resume / Skip on the wrist): move this player to
    /// match. Applied without sending an anchor back, so the two can't echo.
    private func applyWatchAnchor(_ anchor: ClockAnchor?) {
        #if os(iOS)
        guard let incoming = anchor, isPlaying, let plan, plan.id == incoming.planID else { return }
        // Adopt it as our own clock reference, then move the display to match.
        self.anchor = incoming
        let position = PlanClock.position(plan: plan, anchor: incoming, at: Date().timeIntervalSince1970)

        func recordCurrentAsDone() {
            if let ex = currentExercise, ex.name != "Rest" { completedExerciseNames.append(ex.name) }
        }

        if position.isFinished {
            // Skipped past the last slot: close out the routine the way a normal finish does.
            while currentIndex < routine.count - 1 {
                recordCurrentAsDone()
                currentIndex += 1
            }
            nextExercise()
            return
        }

        let moved = position.slotIndex > currentIndex
        while currentIndex < position.slotIndex {
            recordCurrentAsDone()
            currentIndex += 1
        }
        timeRemaining = position.remaining
        if moved {
            prepareVideoForCurrentExercise(autoplay: incoming.isRunning)
            playFeedback(transitionFeedback(enteringIndex: currentIndex))
        }
        let shouldPause = !incoming.isRunning
        if isPaused != shouldPause {
            isPaused = shouldPause
            if isPaused { avPlayer?.pause() } else { avPlayer?.play() }
        }
        sendWorkoutStateToWatch()
        #endif
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
        connectivityManager.sendPrepareToStart(activityTypeRaw: resolvedActivityType.rawValue)
        launchWatchWorkoutSession()
#endif
    }
    
    #if canImport(HealthKit)
    /// Classifies the session for HealthKit based on which focus areas were selected,
    /// falling back to the chosen intention when the areas don't point at one specific
    /// activity (e.g. a mixed Chest/Legs/Shoulders session).
    private var resolvedActivityType: HKWorkoutActivityType {
        SavedRoutineKind.forFocusAreas(selectedFocusAreas).healthKitActivityType
            ?? intention.healthKitActivityType
    }
    #endif

    private func launchWatchWorkoutSession() {
        #if os(iOS)
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Health access comes first, on the iPhone: if the user hasn't answered yet, ask here
        // before the Watch app is launched, so the Watch is never where they're first asked.
        let store = HKHealthStore()
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = resolvedActivityType
        configuration.locationType = .indoor
        Task { @MainActor in
            await HRZoneSettings.shared.requestHealthAccessIfNeeded()
            store.startWatchApp(with: configuration) { success, error in
                if let error = error {
                    print("Failed to launch watch app: \(error.localizedDescription)")
                } else if success {
                    print("Watch app launched for workout session")
                }
            }
        }
        #endif
    }
    
    /// Starts the clock. The timer only *prompts* a look at the time: what the player shows comes
    /// from the plan and anchor (`clockTick`), so a late or paused tick costs nothing. It runs in
    /// the common run-loop modes so it keeps firing while the user scrolls the player.
    private func startTimer() {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: 0.25, repeats: true) { _ in
            clockTick()
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    /// Works out where the plan stands now and brings the player in line: advances through any
    /// slots the clock has passed, then sets the countdown from `PlanClock` — the same math, and
    /// the same rounding (whole seconds, rounded up), as the Apple Watch.
    private func clockTick() {
        guard isPlaying, !isPaused, let plan, let anchor else { return }
        let position = PlanClock.position(plan: plan, anchor: anchor, at: Date().timeIntervalSince1970)
        let previousRemaining = timeRemaining

        // Leave any slot the clock has already moved past (usually one; more after a long stall).
        let target = min(position.slotIndex, routine.count)
        while currentIndex < target {
            countSeconds(timeRemaining)          // what was left of the slot we're leaving
            playFeedback(.end)
            nextExercise()                       // next slot, or the end of the routine
            if currentIndex >= routine.count { return }
        }
        guard currentIndex < routine.count else { return }

        let remaining = position.remaining
        if remaining < timeRemaining {
            countSeconds(timeRemaining - remaining)
            timeRemaining = remaining
            secondElapsed(remaining: remaining)
        } else if remaining != timeRemaining {
            timeRemaining = remaining            // the clock reference moved (e.g. a Watch skip)
        }
        if remaining == 3 && previousRemaining != 3 {
            playFeedback(.warning)
        }
    }

    /// Adds whole seconds to the exercise or rest total for the slot we're in.
    private func countSeconds(_ seconds: Int) {
        guard seconds > 0, currentIndex < routine.count else { return }
        if isRest { totalRestTime += seconds } else { totalExerciseTime += seconds }
    }

    /// Per-second work: heart-rate sampling for the recap, the intention banner check, and the
    /// timer message older Watch builds still use (new ones derive time from the plan).
    private func secondElapsed(remaining: Int) {
        #if os(iOS)
        let currentExerciseTime = totalExerciseTime
        Task { @MainActor in
            let hr = connectivityManager.heartRate
            if hr > 0 {
                heartRateSamples.append(hr)
                if hr > peakHeartRate { peakHeartRate = hr }
                // Check HR/intention alignment every 30 seconds of exercise.
                if !isRest && currentExerciseTime >= 30
                    && currentExerciseTime / 30 > max(lastBannerExerciseTime, 0) / 30 {
                    lastBannerExerciseTime = currentExerciseTime
                    let zone = hrZoneName(bpm: hr)
                    if zone == "Zone 4" || zone == "Zone 5" {
                        highIntensityStreakSeconds += 30
                    } else {
                        highIntensityStreakSeconds = 0
                    }
                    showIntentionBannerIfNeeded(hr: hr)
                }
            }
            connectivityManager.sendTimerUpdate(timeRemaining: remaining)
        }
        #endif
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
                self.recapIsFullScreen = self.horizontalSizeClass == .regular
                self.showingRecap = true
            }
            return
        }

        timeRemaining = durationForCurrentPosition
        prepareVideoForCurrentExercise(autoplay: true)
        playFeedback(transitionFeedback(enteringIndex: currentIndex))
        sendWorkoutStateToWatch()
    }

    /// `.start` for an ordinary slot change; a distinct cue right at the seam between
    /// warm-up and the first work exercise, or between the last work exercise and the
    /// cool-down. Preparation slots (warm-up/cool-down, including the rest between
    /// warm-up and work) are marked by `isPreparation`; a plain work/rest slot never is.
    private func transitionFeedback(enteringIndex index: Int) -> FeedbackEvent {
        guard index > 0, index < routine.count else { return .start }
        let leaving = routine[index - 1].isPreparation
        let entering = routine[index].isPreparation
        if leaving && !entering { return .enterActive }
        if !leaving && entering { return .enterCoolDown }
        return .start
    }

    private func togglePause() {
        isPaused.toggle()
        playFeedback(.warning)
        if let plan, let current = anchor {
            let now = Date().timeIntervalSince1970
            anchor = isPaused
                ? PlanClock.paused(plan, current, at: now, by: .phone)
                : PlanClock.resumed(plan, current, at: now, by: .phone)
        }
        sendPhoneAnchor()
        sendWorkoutStateToWatch()
        #if os(iOS)
        connectivityManager.sendControlMessage(isPaused ? .workoutPaused : .workoutResumed)
        #endif
        if isPaused { avPlayer?.pause() } else { avPlayer?.play() }
    }
    
    private func skipExercise() {
        playFeedback(.warning)
        // The skip moves the clock reference to the start of the next slot.
        if let plan, let current = anchor {
            anchor = PlanClock.skipped(plan, current, at: Date().timeIntervalSince1970, by: .phone)
        }
        nextExercise()
        // A skip is a jump the Watch can't derive; tell it where we landed. (If that was the end,
        // the completion message covers it.)
        if currentIndex < routine.count { sendPhoneAnchor() }
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

    private func hrZoneName(bpm: Double) -> String {
        #if os(iOS)
        // The Watch's own zone first, then its boundaries, and only then the age-based fallback.
        return ZoneResolver.resolve(heartRate: bpm,
                                    watchZoneIndex: connectivityManager.watchZoneIndex,
                                    liveThresholds: connectivityManager.watchZoneThresholds).name
        #else
        return HRZoneSettings.shared.zoneName(forHeartRate: bpm)
        #endif
    }

    // Zones 4-5 are meant for short bursts (per standard HR zone guidance: Zone 5 is
    // "unsustainable for more than 1-3 minutes", Zone 4 is "only short phases possible").
    // Once a continuous high-intensity streak crosses this, stop cheering the user on
    // and nudge them to recover instead — regardless of intention.
    private let highIntensitySafetyThresholdSeconds = 180

    private func intentionBannerPayload(hr: Double) -> IntentionBannerPayload? {
        let zone = hrZoneName(bpm: hr)

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

        // HIIT
        case (.hiit, "Zone 1"), (.hiit, "Zone 2"):
            return IntentionBannerPayload(message: "That's rest-interval effort — go all-out on the next work interval!", icon: "arrow.up.circle.fill", tone: .nudgeUp)
        case (.hiit, "Zone 3"):
            return IntentionBannerPayload(message: "Closer — HIIT wants one more gear out of you!", icon: "arrow.up.circle.fill", tone: .nudgeUp)
        case (.hiit, "Zone 4"), (.hiit, "Zone 5"):
            return IntentionBannerPayload(message: "That's the HIIT effort you're after — max out this interval! ⚡️", icon: "bolt.heart.fill", tone: .positive)

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
