import SwiftUI
#if canImport(AVFoundation)
import AVFoundation
#endif
#if os(macOS)
import AppKit
#endif

// MARK: - Stretch Routine Setup

struct StretchRoutineView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var catalog = ExerciseCatalog.shared
    @State private var selectedCategories: Set<String> = []
    @State private var holdDuration: Int = 20
    @State private var maxTotalMinutes: Int = 0   // 0 = no limit
    @State private var isOrdered: Bool = true
    @State private var bothSidesMode: Bool = true
    @State private var generatedStretches: [Exercise] = []
    @State private var showingPlayer = false
    @State private var completedStretchSession = false
#if os(iOS)
    @State private var showingWatchHandoff = false
    @State private var startStretchAfterHandoff = false
#endif

    private let holdDurationOptions = [10, 15, 20, 30]

    private var stretchCategories: [String] {
        catalog.focusAreas.filter { area in
            ["Stretch", "Recovery", "Cool Down", "Warm-Up"].contains { area.contains($0) }
        }
    }

    private func categoryIcon(_ category: String) -> String {
        if category.contains("Morning") { return "sunrise.fill" }
        if category.contains("Evening") { return "moon.stars.fill" }
        if category.contains("Cool Down") { return "figure.cooldown" }
        if category.contains("Hips") { return "figure.flexibility" }
        if category.contains("Full Body") { return "figure.run" }
        return "figure.cooldown"
    }

    private func categoryColor(_ category: String) -> Color {
        if category.contains("Morning") { return .yellow }
        if category.contains("Evening") { return .indigo }
        if category.contains("Cool Down") { return .teal }
        if category.contains("Hips") { return .orange }
        if category.contains("Full Body") { return .green }
        return .teal
    }

    private func categoryShortLabel(_ category: String) -> String {
        if category.contains("Morning") { return "Morning" }
        if category.contains("Evening") { return "Evening" }
        if category.contains("Cool Down") { return "Cool Down" }
        if category.contains("Hips") { return "Hips" }
        if category.contains("Full Body") { return "Full Body" }
        return category
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Category selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Stretch Category")
                        .font(.title2)
                        .fontWeight(.semibold)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            let allSelected = selectedCategories.count == stretchCategories.count
                            Button {
                                selectedCategories = allSelected ? [] : Set(stretchCategories)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "figure.cooldown")
                                    Text("All")
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(allSelected ? Color.teal : Color.gray.opacity(0.15))
                                .foregroundStyle(allSelected ? .white : .primary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            ForEach(stretchCategories, id: \.self) { category in
                                let isSelected = selectedCategories.contains(category)
                                let color = categoryColor(category)
                                Button {
                                    if isSelected {
                                        selectedCategories.remove(category)
                                    } else {
                                        selectedCategories.insert(category)
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: categoryIcon(category))
                                        Text(categoryShortLabel(category))
                                    }
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(isSelected ? color : Color.gray.opacity(0.15))
                                    .foregroundStyle(isSelected ? .white : .primary)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                // Hold duration
                VStack(alignment: .leading, spacing: 12) {
                    Text("Hold Duration")
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack(spacing: 8) {
                        ForEach(holdDurationOptions, id: \.self) { sec in
                            Button {
                                holdDuration = sec
                            } label: {
                                Text("\(sec)s")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(holdDuration == sec ? Color.teal : Color.gray.opacity(0.15))
                                    .foregroundStyle(holdDuration == sec ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }

                    Text("Time to hold each stretch per side")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Both sides mode
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $bothSidesMode) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.left.arrow.right")
                                .foregroundStyle(.teal)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Both Sides")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Repeats single-sided stretches on left then right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                }

                // Total time limit
                VStack(alignment: .leading, spacing: 12) {
                    Text("Total Time Limit")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Stepper(value: $maxTotalMinutes, in: 0...60) {
                        HStack {
                            Text("Time limit")
                                .font(.subheadline)
                            Spacer()
                            Text(maxTotalMinutes == 0 ? "No limit" : "\(maxTotalMinutes) min")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if maxTotalMinutes > 0 {
                        Text("Routine will be trimmed to fit within \(maxTotalMinutes) minutes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Order
                VStack(alignment: .leading, spacing: 8) {
                    Text("Order")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Toggle(isOn: $isOrdered) {
                        HStack(spacing: 8) {
                            Image(systemName: isOrdered ? "list.number" : "shuffle")
                                .foregroundStyle(.teal)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isOrdered ? "Fixed Order" : "Randomized")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(isOrdered ? "Stretches play in the listed sequence" : "Stretches are shuffled into a random order")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                }

                // Generate button
                Button {
                    generateStretches()
                } label: {
                    Text("Generate Stretch Routine")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedCategories.isEmpty ? Color.gray : Color.teal)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(selectedCategories.isEmpty)

                // Preview
                if !generatedStretches.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Routine Preview")
                            .font(.title2)
                            .fontWeight(.semibold)

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(generatedStretches.enumerated()), id: \.offset) { index, stretch in
                                HStack {
                                    Text("\(index + 1).")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, alignment: .leading)
                                    Text(stretch.name)
                                        .font(.subheadline)
                                    Spacer()
                                    if bothSidesMode && stretch.singleSided {
                                        Image(systemName: "arrow.left.arrow.right")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(bothSidesMode && stretch.singleSided ? "\(holdDuration)s × 2" : "\(holdDuration)s")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        Button {
#if os(iOS)
                            showingWatchHandoff = true
#else
                            showingPlayer = true
#endif
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Start Stretch Routine")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.teal)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Stretch Routine")
        .sheet(isPresented: $showingPlayer, onDismiss: {
            if completedStretchSession {
                completedStretchSession = false
                dismiss()
            }
        }) {
            StretchPlayerView(
                stretches: generatedStretches,
                holdDuration: holdDuration,
                bothSidesMode: bothSidesMode,
                onComplete: { completedStretchSession = true }
            )
        }
#if os(iOS)
        .sheet(isPresented: $showingWatchHandoff, onDismiss: {
            if startStretchAfterHandoff {
                startStretchAfterHandoff = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showingPlayer = true
                }
            }
        }) {
            WatchHandoffView { startStretchAfterHandoff = true }
        }
#endif
        .onAppear {
            if selectedCategories.isEmpty, let first = stretchCategories.first {
                selectedCategories = [first]
            }
        }
    }

    private func generateStretches() {
        var pool: [Exercise] = []
        for category in stretchCategories where selectedCategories.contains(category) {
            if let difficultyDict = catalog.exercises[category] {
                for (_, exerciseList) in difficultyDict {
                    pool.append(contentsOf: exerciseList)
                }
            }
        }
        var result = isOrdered ? pool : pool.shuffled()

        if maxTotalMinutes > 0 {
            let limitSec = maxTotalMinutes * 60
            var accumulated = 0
            var count = 0
            for stretch in result {
                let sides = (bothSidesMode && stretch.singleSided) ? 2 : 1
                let slotSec = holdDuration * sides + StretchPlayerView.transitionDuration
                if accumulated + slotSec > limitSec { break }
                accumulated += slotSec
                count += 1
            }
            result = Array(result.prefix(max(1, count)))
        }

        generatedStretches = result
    }
}

// MARK: - Stretch Player

struct StretchPlayerView: View {
    let stretches: [Exercise]
    let holdDuration: Int
    let bothSidesMode: Bool
    var onComplete: (() -> Void)? = nil

    @State private var currentIndex = 0
    @State private var currentSide = 0   // 0 = first/left, 1 = second/right
    @State private var isTransitioning = false
    @State private var timeRemaining = 0
    @State private var isPlaying = false
    @State private var isPaused = false
    @State private var timer: Timer?
    @State private var showingRecap = false
    @Environment(\.dismiss) private var dismiss

    // Audio + Watch feedback
    @State private var audioEngine: AVAudioEngine?
    @State private var playerNode: AVAudioPlayerNode?
    @StateObject private var connectivityManager = WorkoutConnectivityManager.shared

    static let transitionDuration = 5

    var currentStretch: Exercise? {
        guard currentIndex < stretches.count else { return nil }
        return stretches[currentIndex]
    }

    private var timerProgress: CGFloat {
        guard isPlaying else { return 1 }
        let total = isTransitioning ? Self.transitionDuration : holdDuration
        return CGFloat(timeRemaining) / CGFloat(max(1, total))
    }

    // "Hold" for static stretches, "Move" for dynamic/circular ones
    private var actionLabel: String {
        guard let name = currentStretch?.name else { return "Hold" }
        let lower = name.lowercased()
        let dynamicKeywords = ["circle", "rotation", "swing", "roll", "dynamic",
                               "mobilit", "oscillat", "bounce", "pendulum", "windmill",
                               "hydrant", "clamshell", "walk-out", "march"]
        return dynamicKeywords.contains(where: { lower.contains($0) }) ? "Move" : "Hold"
    }

    private var sideLabel: String? {
        guard bothSidesMode && !isTransitioning && isPlaying else { return nil }
        guard let stretch = currentStretch, stretch.singleSided else { return nil }
        return currentSide == 0 ? "Left Side" : "Right Side"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
                    // Phase label
                    if isPlaying {
                        HStack(spacing: 8) {
                            Text(isTransitioning ? "Get Ready" : actionLabel)
                                .font(.headline)
                                .foregroundStyle(isTransitioning ? .orange : .teal)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background((isTransitioning ? Color.orange : Color.teal).opacity(0.15))
                                .clipShape(Capsule())

                            if let side = sideLabel {
                                Text(side)
                                    .font(.headline)
                                    .foregroundStyle(.indigo)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                    .background(Color.indigo.opacity(0.15))
                                    .clipShape(Capsule())
                                    .transition(.opacity.combined(with: .scale))
                            }
                        }
                        .animation(.easeInOut(duration: 0.25), value: currentSide)
                    }

                    // Stretch name
                    Text(currentStretch?.name ?? "Complete!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .animation(.default, value: currentIndex)

                    // Timer ring
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.15), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: timerProgress)
                            .stroke(
                                isTransitioning ? Color.orange : Color.teal,
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: timeRemaining)
                        Text(isPlaying ? "\(timeRemaining)" : "\(holdDuration)")
                            .font(.system(size: 56, weight: .bold, design: .monospaced))
                            .foregroundStyle(timeRemaining <= 3 && isPlaying ? .red : .primary)
                    }
                    .frame(width: 160, height: 160)

                    // Progress
                    if !stretches.isEmpty {
                        VStack(spacing: 2) {
                            Text("Stretch \(min(currentIndex + 1, stretches.count)) of \(stretches.count)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if bothSidesMode, !isTransitioning, isPlaying,
                               let stretch = currentStretch, stretch.singleSided {
                                Text(currentSide == 0 ? "First side" : "Second side")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .animation(.easeInOut, value: currentSide)
                            }
                        }
                    }
                }

                Spacer()

                // Controls
                HStack(spacing: 40) {
                    if !isPlaying {
                        Button { startRoutine() } label: {
                            controlButton(icon: "play.fill", label: "Start", color: .teal)
                        }
                    } else {
                        Button { togglePause() } label: {
                            controlButton(
                                icon: isPaused ? "play.fill" : "pause.fill",
                                label: isPaused ? "Resume" : "Pause",
                                color: .blue
                            )
                        }
                        Button { skipCurrent() } label: {
                            controlButton(icon: "forward.fill", label: "Skip", color: .orange)
                        }
                    }
                }
                .padding(.vertical, 24)
            }
            .navigationTitle("Stretching")
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
        .onAppear { timeRemaining = holdDuration }
        .onDisappear { stopRoutine() }
        .sheet(isPresented: $showingRecap) {
            StretchRecapView(
                stretches: stretches,
                holdDuration: holdDuration,
                bothSidesMode: bothSidesMode,
                onDismiss: {
                    onComplete?()
                    showingRecap = false
                    dismiss()
                }
            )
        }
    }

    @ViewBuilder
    private func controlButton(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 30))
            Text(label)
                .font(.caption)
        }
        .frame(width: 80, height: 80)
        .background(color)
        .foregroundStyle(.white)
        .clipShape(Circle())
    }

    private func startRoutine() {
        isPlaying = true
        isTransitioning = false
        currentSide = 0
        timeRemaining = holdDuration
        startTimer()
        playFeedback(.start)
        sendWorkoutStateToWatch()
    }

    private func togglePause() {
        isPaused.toggle()
        sendWorkoutStateToWatch()
    }

    private func skipCurrent() { advance() }

    private func advance() {
        // Transition done → start holding
        if isTransitioning {
            isTransitioning = false
            timeRemaining = holdDuration
            playFeedback(.start)
            sendWorkoutStateToWatch()
            return
        }

        // Finished first side of a single-sided stretch → switch to second side
        if bothSidesMode, currentSide == 0, let stretch = currentStretch, stretch.singleSided {
            currentSide = 1
            timeRemaining = holdDuration
            playFeedback(.start)
            return
        }

        // Move to next stretch
        currentIndex += 1
        currentSide = 0

        if currentIndex >= stretches.count {
            timer?.invalidate()
            timer = nil
            isPlaying = false
            playFeedback(.complete)
            sendControlToWatch(.workoutStopped)
            showingRecap = true
            return
        }

        isTransitioning = true
        timeRemaining = Self.transitionDuration
        playFeedback(.start)
        sendWorkoutStateToWatch()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard !isPaused else { return }
            timeRemaining -= 1
            let t = timeRemaining
            Task { @MainActor in connectivityManager.sendTimerUpdate(timeRemaining: t) }
            if timeRemaining == 3 && !isTransitioning {
                playFeedback(.warning)
            }
            if timeRemaining <= 0 {
                if !isTransitioning { playFeedback(.end) }
                advance()
            }
        }
    }

    private func stopRoutine() {
        timer?.invalidate()
        timer = nil
        sendControlToWatch(.workoutStopped)
#if canImport(AVFoundation)
        playerNode?.stop()
        audioEngine?.stop()
#endif
    }

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
            do {
                try engine.start()
            } catch {
                // Ignore errors; will retry on first feedback
            }
        }
    #endif
#endif
    }

    private func playFeedback(_ event: FeedbackEvent) {
        triggerHaptic(for: event)
        sendFeedbackToWatch(event)
#if os(macOS)
        switch event {
        case .start:
            NSSound.beep()
        case .warning:
            NSSound.beep(); NSSound.beep()
        case .end:
            NSSound.beep(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { NSSound.beep() }
        case .complete:
            NSSound.beep()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSSound.beep() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { NSSound.beep() }
        }
        return
#endif
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
        _ = generator
        #endif
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

    private func sendWorkoutStateToWatch() {
        #if os(iOS)
        let nextName: String? = (currentIndex + 1 < stretches.count) ? stretches[currentIndex + 1].name : nil
        let state = WorkoutState(
            currentExerciseName: isTransitioning ? "Get Ready" : (currentStretch?.name ?? "Complete"),
            currentIndex: currentIndex,
            totalExercises: stretches.count,
            timeRemaining: timeRemaining,
            isRest: isTransitioning,
            nextExerciseName: isTransitioning ? currentStretch?.name : nextName,
            isPlaying: isPlaying,
            isPaused: isPaused
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

// MARK: - Stretch Recap

struct StretchRecapView: View {
    let stretches: [Exercise]
    let holdDuration: Int
    let bothSidesMode: Bool
    let onDismiss: () -> Void

    private var totalHoldSeconds: Int {
        stretches.reduce(0) { total, stretch in
            total + holdDuration * (bothSidesMode && stretch.singleSided ? 2 : 1)
        }
    }
    private var totalTimeSeconds: Int {
        totalHoldSeconds + max(0, stretches.count - 1) * StretchPlayerView.transitionDuration
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.teal)
                        Text("Stretch Complete!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    .padding(.top, 8)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        RecapStatCard(title: "Total Time",  value: formatted(totalTimeSeconds), icon: "clock",               color: .blue)
                        RecapStatCard(title: "Stretches",  value: "\(stretches.count)",        icon: "figure.cooldown",     color: .teal)
                        RecapStatCard(title: "Hold / Side", value: "\(holdDuration)s",         icon: "timer",               color: .green)
                        if bothSidesMode {
                            RecapStatCard(title: "Both Sides", value: "Yes",                   icon: "arrow.left.arrow.right", color: .indigo)
                        }
                    }

                    if !stretches.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Stretches Completed")
                                .font(.headline)
                            ForEach(Array(stretches.enumerated()), id: \.offset) { i, stretch in
                                HStack {
                                    Text("\(i + 1).")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, alignment: .leading)
                                    Text(stretch.name)
                                        .font(.subheadline)
                                    if stretch.singleSided && bothSidesMode {
                                        Spacer()
                                        Image(systemName: "arrow.left.arrow.right")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding()
            }
            .navigationTitle("Recap")
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { onDismiss() }
                        .fontWeight(.semibold)
                }
            }
#else
            .toolbar {
                ToolbarItem {
                    Button("Done") { onDismiss() }
                        .fontWeight(.semibold)
                }
            }
#endif
        }
    }

    private func formatted(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
