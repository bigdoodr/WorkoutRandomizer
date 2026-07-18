import SwiftUI
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(HealthKit)
import HealthKit
#endif

// MARK: - Models

enum SavedMoveType: String {
    case hold = "Hold"
    case move = "Move"
}

struct SavedRoutineExercise: Identifiable {
    let id = UUID()
    let name: String
    let duration: Int           // work/hold seconds per side
    let restDuration: Int       // rest after exercise (or after each side if restAfterEachSide)
    let singleSided: Bool
    let restAfterEachSide: Bool // for single-sided: rest after L and after R separately
    let moveType: SavedMoveType

    init(
        name: String,
        duration: Int,
        restDuration: Int = 0,
        singleSided: Bool = false,
        restAfterEachSide: Bool = false,
        moveType: SavedMoveType = .hold
    ) {
        self.name = name
        self.duration = duration
        self.restDuration = restDuration
        self.singleSided = singleSided
        self.restAfterEachSide = restAfterEachSide
        self.moveType = moveType
    }
}

struct SavedWorkoutRoutine: Identifiable {
    let id = UUID()
    let name: String
    let routineDescription: String
    let source: String
    let sourceURL: String
    let exercises: [SavedRoutineExercise]
    let accentColor: Color

    var totalDurationSeconds: Int {
        exercises.reduce(0) { total, ex in
            let sides = (ex.singleSided) ? 2 : 1
            let work = ex.duration * sides
            let rest: Int
            if ex.singleSided && ex.restAfterEachSide {
                rest = ex.restDuration * 2
            } else {
                rest = ex.restDuration
            }
            return total + work + rest
        }
    }

    var formattedDuration: String {
        let s = totalDurationSeconds
        let m = s / 60
        let sec = s % 60
        return sec == 0 ? "\(m) min" : "\(m)m \(sec)s"
    }
}

// MARK: - Pre-loaded Athlean-X Routines

enum PreloadedRoutines {
    static let all: [SavedWorkoutRoutine] = [morningStretches, bedtimeStretches, absWorkout]

    static let morningStretches = SavedWorkoutRoutine(
        name: "5 Stretches Every Morning",
        routineDescription: "A full-body morning stretch sequence to loosen up your hips, back, and lower body. Do this before you start your day.",
        source: "Athlean-X",
        sourceURL: "https://youtu.be/eU2y-i7mt5Q?si=3pNLFzsHEhxZgU3M",
        exercises: [
            SavedRoutineExercise(name: "Squat Fold",            duration: 60, singleSided: false, moveType: .hold),
            SavedRoutineExercise(name: "Side Bridge & Reach",   duration: 30, singleSided: true,  moveType: .hold),
            SavedRoutineExercise(name: "QL Pull Through",       duration: 30, singleSided: true,  moveType: .hold),
            SavedRoutineExercise(name: "Hip Switch & Lean",     duration: 30, singleSided: true,  moveType: .hold),
            SavedRoutineExercise(name: "London Bridge",         duration: 30, singleSided: true,  moveType: .move),
        ],
        accentColor: .yellow
    )

    static let bedtimeStretches = SavedWorkoutRoutine(
        name: "Do This Right Before Bed",
        routineDescription: "A calming evening stretch routine to release tension and prepare your body for sleep.",
        source: "Athlean-X",
        sourceURL: "https://youtu.be/0JeQlfQ5iCg?si=_xYp3xxabq-H0omR",
        exercises: [
            SavedRoutineExercise(name: "Calf & Hamstring Wall Stretch", duration: 30, singleSided: true,  moveType: .hold),
            SavedRoutineExercise(name: "Child's Pose",                  duration: 30, singleSided: false, moveType: .hold),
            SavedRoutineExercise(name: "Lifted Hands Child's Pose",     duration: 30, singleSided: false, moveType: .hold),
            SavedRoutineExercise(name: "Modified Pigeon Pose",          duration: 30, singleSided: true,  moveType: .hold),
            SavedRoutineExercise(name: "Supine Spinal Twist",           duration: 30, singleSided: true,  moveType: .hold),
        ],
        accentColor: .indigo
    )

    static let absWorkout = SavedWorkoutRoutine(
        name: "10 Minute Ab Workout",
        routineDescription: "A complete core circuit hitting every angle of your abs. 45 seconds on, 15 seconds rest. No equipment needed.",
        source: "Athlean-X",
        sourceURL: "https://youtu.be/i27K2ry9jEo?si=hetZqCfQWyWpgpXZ",
        exercises: [
            SavedRoutineExercise(name: "Crescent Tucks",         duration: 45, restDuration: 15, singleSided: false, restAfterEachSide: false, moveType: .move),
            SavedRoutineExercise(name: "Backward 7s",            duration: 45, restDuration: 15, singleSided: false, restAfterEachSide: false, moveType: .move),
            SavedRoutineExercise(name: "Swipers",                duration: 45, restDuration: 15, singleSided: false, restAfterEachSide: false, moveType: .move),
            SavedRoutineExercise(name: "Side Cycles",            duration: 45, restDuration: 15, singleSided: true,  restAfterEachSide: true,  moveType: .move),
            SavedRoutineExercise(name: "Mountain Hip Dips",      duration: 45, restDuration: 15, singleSided: false, restAfterEachSide: false, moveType: .move),
            SavedRoutineExercise(name: "Frog V-Ups",             duration: 45, restDuration: 15, singleSided: false, restAfterEachSide: false, moveType: .move),
            SavedRoutineExercise(name: "Side Scissor Crunches",  duration: 45, restDuration: 15, singleSided: true,  restAfterEachSide: true,  moveType: .move),
            SavedRoutineExercise(name: "Corpse Crunch",          duration: 45, restDuration: 0,  singleSided: false, restAfterEachSide: false, moveType: .move),
        ],
        accentColor: .orange
    )
}

// MARK: - Saved Routines List

struct SavedRoutinesView: View {
    private let routines = PreloadedRoutines.all

    var body: some View {
        List {
            Section {
                ForEach(routines) { routine in
                    NavigationLink(destination: SavedRoutineDetailView(routine: routine)) {
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(routine.accentColor)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Image(systemName: routine.accentColor == .orange ? "figure.core.training" :
                                          routine.accentColor == .yellow ? "sunrise.fill" : "moon.stars.fill")
                                        .foregroundStyle(.white)
                                        .font(.title3)
                                }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(routine.name)
                                    .font(.body)
                                    .fontWeight(.medium)
                                HStack(spacing: 6) {
                                    Text(routine.source)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("·")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(routine.exercises.count) exercises")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("·")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(routine.formattedDuration)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Athlean-X Routines")
            } footer: {
                Text("More routines coming soon. Import your own via the Export button on any generated workout.")
                    .font(.caption)
            }
        }
        .navigationTitle("Saved Routines")
    }
}

// MARK: - Routine Detail

struct SavedRoutineDetailView: View {
    let routine: SavedWorkoutRoutine
    @State private var showingPlayer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(routine.source)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Text(routine.name)
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(routine.formattedDuration)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(routine.accentColor)
                            Text("total")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(routine.routineDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !routine.sourceURL.isEmpty, let url = URL(string: routine.sourceURL) {
                        Link(destination: url) {
                            Label("Watch on YouTube", systemImage: "play.rectangle.fill")
                                .font(.caption)
                                .foregroundStyle(routine.accentColor)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding()
                .background(.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Exercise list
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exercises")
                        .font(.title3)
                        .fontWeight(.semibold)

                    ForEach(Array(routine.exercises.enumerated()), id: \.offset) { index, ex in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 22, alignment: .trailing)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.name)
                                    .font(.subheadline)
                                HStack(spacing: 6) {
                                    Text(ex.moveType.rawValue)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(ex.moveType == .hold ? Color.teal.opacity(0.15) : Color.orange.opacity(0.15))
                                        .foregroundStyle(ex.moveType == .hold ? .teal : .orange)
                                        .clipShape(Capsule())
                                    if ex.singleSided {
                                        Text("Each side")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(ex.duration)s")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(routine.accentColor)
                                if ex.restDuration > 0 {
                                    Text("+ \(ex.restDuration)s rest")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(.gray.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                // Start button
                Button {
                    showingPlayer = true
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Routine")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(routine.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .navigationTitle(routine.name)
#if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .sheet(isPresented: $showingPlayer) {
            SavedRoutinePlayerView(routine: routine)
        }
    }
}

// MARK: - Player Step Model

private struct PlayerStep: Identifiable {
    let id = UUID()
    let label: String
    let sideLabel: String?
    let duration: Int
    let isRest: Bool
    let accentColor: Color
}

// MARK: - Saved Routine Player

struct SavedRoutinePlayerView: View {
    let routine: SavedWorkoutRoutine

    @State private var steps: [PlayerStep] = []
    @State private var currentIndex = 0
    @State private var timeRemaining = 0
    @State private var isPlaying = false
    @State private var isPaused = false
    @State private var timer: Timer?
    @State private var showingRecap = false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var connectivityManager = WorkoutConnectivityManager.shared

#if canImport(AVFoundation)
    @State private var audioEngine: AVAudioEngine?
    @State private var playerNode: AVAudioPlayerNode?
#endif

    private var currentStep: PlayerStep? {
        guard currentIndex < steps.count else { return nil }
        return steps[currentIndex]
    }

    private var timerProgress: Double {
        guard let step = currentStep, step.duration > 0 else { return 1 }
        return Double(timeRemaining) / Double(step.duration)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 20) {
                    Spacer(minLength: 0)

                    // Step name
                    VStack(spacing: 6) {
                        if let step = currentStep {
                            if let side = step.sideLabel {
                                Text(side)
                                    .font(.subheadline)
                                    .foregroundStyle(routine.accentColor)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 4)
                                    .background(routine.accentColor.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            Text(step.label)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        } else {
                            Text("Complete!")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                        }
                    }

                    // Timer ring
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.15), lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: timerProgress)
                            .stroke(
                                currentStep?.isRest == true ? Color.blue : routine.accentColor,
                                style: StrokeStyle(lineWidth: 10, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: timeRemaining)
                        Text(isPlaying ? "\(timeRemaining)" : "\(currentStep?.duration ?? 0)")
                            .font(.system(size: 64, weight: .bold, design: .monospaced))
                            .foregroundStyle(timeRemaining <= 3 && isPlaying ? .red : .primary)
                    }
                    .frame(width: 180, height: 180)

                    // Progress
                    if !steps.isEmpty {
                        Text("Step \(min(currentIndex + 1, steps.count)) of \(steps.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()

                // Controls
                VStack(spacing: 6) {
                    HStack(spacing: 40) {
                        if !isPlaying {
                            Button { startRoutine() } label: {
                                controlCircle(icon: "play.fill", label: "Start", color: routine.accentColor)
                            }
                        } else {
                            Button { togglePause() } label: {
                                controlCircle(
                                    icon: isPaused ? "play.fill" : "pause.fill",
                                    label: isPaused ? "Resume" : "Pause",
                                    color: .blue
                                )
                            }
                            Button { skipStep() } label: {
                                controlCircle(icon: "forward.fill", label: "Skip", color: .orange)
                            }
                        }
                    }
#if os(iOS)
                    if !isPlaying {
                        let msg = connectivityManager.isWatchReachable
                            ? "You can also start from your Apple Watch"
                            : connectivityManager.isWatchConnected
                                ? "Watch Connected"
                                : "Looking for Watch…"
                        Label(msg, systemImage: "applewatch")
                            .font(.caption)
                            .foregroundStyle(connectivityManager.isWatchReachable ? .secondary : .tertiary)
                    }
#endif
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(.thinMaterial)
                .shadow(radius: 2)
                .padding(.horizontal)
            }
            .navigationTitle("Workout")
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { stopRoutine(); dismiss() }
                }
            }
#else
            .toolbar {
                ToolbarItem { Button("Done") { stopRoutine(); dismiss() } }
            }
#endif
        }
        .onAppear {
            buildSteps()
            if let first = steps.first { timeRemaining = first.duration }
            setupAudio()
            prepareWatchHandoff()
        }
        .onDisappear { stopRoutine() }
#if os(iOS)
        .onChange(of: connectivityManager.watchRequestedStart) { _, requested in
            if requested {
                connectivityManager.watchRequestedStart = false
                if !isPlaying { startRoutine() }
            }
        }
        .onChange(of: connectivityManager.watchRequestedStop) { _, requested in
            if requested {
                connectivityManager.watchRequestedStop = false
                if isPlaying { stopRoutine(); dismiss() }
            }
        }
#endif
        .sheet(isPresented: $showingRecap) {
            SavedRoutineRecapView(routine: routine, onDismiss: { dismiss() })
        }
    }

    private func buildSteps() {
        var result: [PlayerStep] = []
        for ex in routine.exercises {
            if ex.singleSided {
                result.append(PlayerStep(label: ex.name, sideLabel: "Left Side",  duration: ex.duration, isRest: false, accentColor: routine.accentColor))
                if ex.restAfterEachSide && ex.restDuration > 0 {
                    result.append(PlayerStep(label: "Rest", sideLabel: nil, duration: ex.restDuration, isRest: true, accentColor: routine.accentColor))
                }
                result.append(PlayerStep(label: ex.name, sideLabel: "Right Side", duration: ex.duration, isRest: false, accentColor: routine.accentColor))
                if ex.restDuration > 0 {
                    result.append(PlayerStep(label: "Rest", sideLabel: nil, duration: ex.restDuration, isRest: true, accentColor: routine.accentColor))
                }
            } else {
                result.append(PlayerStep(label: ex.name, sideLabel: nil, duration: ex.duration, isRest: false, accentColor: routine.accentColor))
                if ex.restDuration > 0 {
                    result.append(PlayerStep(label: "Rest", sideLabel: nil, duration: ex.restDuration, isRest: true, accentColor: routine.accentColor))
                }
            }
        }
        steps = result
    }

    private func startRoutine() {
        guard !steps.isEmpty else { return }
        isPlaying = true
        isPaused = false
        currentIndex = 0
        timeRemaining = steps[0].duration
        setIdleTimer(disabled: true)
        scheduleTimer()
        playBeep(type: .start)
        sendWorkoutStateToWatch()
        launchWatchWorkoutSession()
    }

    private func togglePause() {
        isPaused.toggle()
        if isPaused {
            timer?.invalidate()
            timer = nil
        } else {
            scheduleTimer()
        }
        sendWorkoutStateToWatch()
        sendControlToWatch(isPaused ? .workoutPaused : .workoutResumed)
    }

    private func skipStep() {
        advance()
    }

    private func stopRoutine() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
        setIdleTimer(disabled: false)
        sendControlToWatch(.workoutStopped)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            tick()
        }
    }

    private func tick() {
        guard isPlaying && !isPaused else { return }
        if timeRemaining > 1 {
            timeRemaining -= 1
            let t = timeRemaining
            connectivityManager.sendTimerUpdate(timeRemaining: t)
            if timeRemaining == 3 { playBeep(type: .warning) }
        } else {
            advance()
        }
    }

    private func advance() {
        playBeep(type: .end)
        let next = currentIndex + 1
        if next < steps.count {
            currentIndex = next
            timeRemaining = steps[next].duration
            sendWorkoutStateToWatch()
        } else {
            timer?.invalidate()
            timer = nil
            isPlaying = false
            setIdleTimer(disabled: false)
            playBeep(type: .complete)
            sendControlToWatch(.workoutStopped)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingRecap = true
            }
        }
    }

    private func setIdleTimer(disabled: Bool) {
#if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = disabled
#endif
    }

    @ViewBuilder
    private func controlCircle(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 28))
            Text(label).font(.caption)
        }
        .frame(width: 80, height: 80)
        .background(color)
        .foregroundStyle(.white)
        .clipShape(Circle())
    }

    // MARK: - Audio

    private func setupAudio() {
#if canImport(AVFoundation)
    #if os(iOS) || os(tvOS) || os(visionOS)
        if audioEngine == nil {
            let engine = AVAudioEngine()
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
            do { try engine.start() } catch { }
        }
    #endif
#endif
    }

    private func playBeep(type: FeedbackEvent) {
        triggerHaptic(for: type)
#if canImport(AVFoundation)
    #if os(iOS) || os(tvOS) || os(visionOS)
        DispatchQueue.global(qos: .utility).async {
            let audioSession = AVAudioSession.sharedInstance()
            _ = try? audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            _ = try? audioSession.setActive(true, options: [])
        }

        if audioEngine == nil || playerNode == nil { setupAudio() }
        guard let engine = audioEngine else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let node: AVAudioPlayerNode
            if let existing = self.playerNode {
                node = existing
            } else {
                let newNode = AVAudioPlayerNode()
                engine.attach(newNode)
                let hwFormat = engine.outputNode.outputFormat(forBus: 0)
                engine.connect(newNode, to: engine.mainMixerNode, format: hwFormat)
                self.playerNode = newNode
                node = newNode
            }

            if !engine.isRunning { try? engine.start() }
            engine.mainMixerNode.outputVolume = 1.0
            engine.mainMixerNode.volume = 1.0

            let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
            let sampleRate = mixerFormat.sampleRate

            let (frequency, duration): (Double, Double)
            switch type {
            case .start:    (frequency, duration) = (880, 0.12)
            case .warning:  (frequency, duration) = (1400, 0.10)
            case .end:      (frequency, duration) = (523.25, 0.22)
            case .complete: (frequency, duration) = (659.25, 0.18)
            }

            let frames = AVAudioFrameCount(sampleRate * duration)
            guard let buf = AVAudioPCMBuffer(pcmFormat: mixerFormat, frameCapacity: frames) else { return }
            buf.frameLength = frames

            let total = Int(frames)
            let channelCount = Int(mixerFormat.channelCount)
            for ch in 0..<channelCount {
                if let data = buf.floatChannelData?[ch] {
                    for i in 0..<total {
                        let t = Double(i) / sampleRate
                        data[i] = Float(sin(2.0 * Double.pi * frequency * t) * 0.6)
                    }
                }
            }

            DispatchQueue.main.async {
                node.scheduleBuffer(buf, completionHandler: nil)
                if !node.isPlaying { node.play() }
            }
        }
    #endif
#endif
    }

    private func triggerHaptic(for event: FeedbackEvent) {
#if os(iOS)
    #if canImport(UIKit)
        switch event {
        case .start:
            let g = UIImpactFeedbackGenerator(style: .medium)
            g.prepare(); g.impactOccurred()
        case .warning:
            let g = UIImpactFeedbackGenerator(style: .rigid)
            g.prepare(); g.impactOccurred(intensity: 1.0)
        case .end:
            let g = UINotificationFeedbackGenerator()
            g.prepare(); g.notificationOccurred(.success)
        case .complete:
            let g = UINotificationFeedbackGenerator()
            g.prepare(); g.notificationOccurred(.success)
        }
    #endif
#endif
    }

    // MARK: - Watch Connectivity

    private func prepareWatchHandoff() {
#if os(iOS)
        guard !isPlaying else { return }
        connectivityManager.watchRequestedStart = false
        connectivityManager.sendPrepareToStart()
        launchWatchWorkoutSession()
#endif
    }

    private func launchWatchWorkoutSession() {
#if canImport(HealthKit)
#if os(iOS)
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .flexibility
        configuration.locationType = .indoor
        store.startWatchApp(with: configuration) { success, error in
            if let error = error {
                print("Failed to launch watch app: \(error.localizedDescription)")
            }
        }
#endif
#endif
    }

    private func sendWorkoutStateToWatch() {
#if os(iOS)
        let step = currentIndex < steps.count ? steps[currentIndex] : nil
        let nextStep = (currentIndex + 1) < steps.count ? steps[currentIndex + 1] : nil
        let state = WorkoutState(
            currentExerciseName: step?.label ?? "Complete",
            currentIndex: currentIndex,
            totalExercises: steps.count,
            timeRemaining: timeRemaining,
            isRest: step?.isRest ?? false,
            nextExerciseName: nextStep?.label,
            isPlaying: isPlaying,
            isPaused: isPaused,
            sideLabel: step?.sideLabel
        )
        connectivityManager.sendWorkoutState(state)
#endif
    }

    private func sendControlToWatch(_ control: ControlMessage) {
#if os(iOS)
        connectivityManager.sendControlMessage(control)
#endif
    }
}

// MARK: - Recap

struct SavedRoutineRecapView: View {
    let routine: SavedWorkoutRoutine
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(routine.accentColor)

                Text("Routine Complete!")
                    .font(.title)
                    .fontWeight(.bold)

                VStack(spacing: 8) {
                    Text(routine.name)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(routine.formattedDuration)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") { onDismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(routine.accentColor)
                    .controlSize(.large)

                Spacer(minLength: 30)
            }
            .navigationTitle("Recap")
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
    }
}
