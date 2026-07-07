import SwiftUI
#if canImport(AVFoundation)
import AVFoundation
#endif
#if os(macOS)
import AppKit
#endif

// MARK: - Stretch Routine Setup

struct StretchRoutineView: View {
    @State private var catalog = ExerciseCatalog.shared
    @State private var selectedCategories: Set<String> = []
    @State private var holdDuration: Int = 45
    @State private var repsPerStretch: Int = 1
    @State private var maxTotalMinutes: Int = 0   // 0 = no limit
    @State private var isOrdered: Bool = true
    @State private var bothSidesMode: Bool = false
    @State private var generatedStretches: [Exercise] = []
    @State private var showingPlayer = false

    private var stretchCategories: [String] {
        catalog.focusAreas.filter { area in
            ["Stretch", "Recovery", "Cool Down", "Warm-Up"].contains { area.contains($0) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Category selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Stretch Category")
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack {
                        Toggle(isOn: Binding(
                            get: { !stretchCategories.isEmpty && selectedCategories.count == stretchCategories.count },
                            set: { newValue in
                                selectedCategories = newValue ? Set(stretchCategories) : []
                            }
                        )) {
                            Text("Select All")
                        }
                        .toggleStyle(.switch)
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                        ForEach(stretchCategories, id: \.self) { category in
                            HStack {
                                Image(systemName: selectedCategories.contains(category) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selectedCategories.contains(category) ? .teal : .secondary)
                                Text(category)
                                    .font(.subheadline)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedCategories.contains(category) {
                                    selectedCategories.remove(category)
                                } else {
                                    selectedCategories.insert(category)
                                }
                            }
                        }
                    }
                }

                // Duration per side
                VStack(alignment: .leading, spacing: 12) {
                    Text("Duration per Side")
                        .font(.title2)
                        .fontWeight(.semibold)
                    HStack {
                        Text("Duration per side")
                            .font(.subheadline)
                        Spacer()
                        Text("\(holdDuration) sec")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(get: { Double(holdDuration) }, set: { holdDuration = Int($0) }),
                        in: 15...90,
                        step: 5
                    ) {
                        Text("Duration per Side")
                    } minimumValueLabel: {
                        Text("15s").font(.caption2)
                    } maximumValueLabel: {
                        Text("90s").font(.caption2)
                    }
                }

                // Reps per stretch
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reps per Stretch")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Stepper(value: $repsPerStretch, in: 1...10) {
                        HStack {
                            Text("Reps per stretch")
                                .font(.subheadline)
                            Spacer()
                            Text("\(repsPerStretch) rep\(repsPerStretch == 1 ? "" : "s")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Both sides mode
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $bothSidesMode) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.left.arrow.right")
                                .foregroundStyle(.teal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Both Sides")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Runs each stretch twice — left then right")
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
                VStack(alignment: .leading, spacing: 12) {
                    Text("Order")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Toggle(isOn: $isOrdered) {
                        HStack(spacing: 6) {
                            Image(systemName: isOrdered ? "list.number" : "shuffle")
                                .foregroundStyle(.teal)
                            Text(isOrdered ? "Fixed order" : "Shuffled")
                                .font(.subheadline)
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
                                    if bothSidesMode {
                                        Text("\(holdDuration)s × \(repsPerStretch) × 2")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("\(holdDuration)s × \(repsPerStretch)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        Button {
                            showingPlayer = true
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
        .sheet(isPresented: $showingPlayer) {
            StretchPlayerView(
                stretches: generatedStretches,
                holdDuration: holdDuration,
                repsPerStretch: repsPerStretch,
                bothSidesMode: bothSidesMode
            )
        }
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
            let sidesMultiplier = bothSidesMode ? 2 : 1
            var accumulated = 0
            var count = 0
            for _ in result {
                let slotSec = holdDuration * repsPerStretch * sidesMultiplier + StretchPlayerView.transitionDuration
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
    let repsPerStretch: Int
    let bothSidesMode: Bool

    @State private var currentIndex = 0
    @State private var currentRep = 1
    @State private var currentSide = 0   // 0 = first/left, 1 = second/right
    @State private var isTransitioning = false
    @State private var timeRemaining = 0
    @State private var isPlaying = false
    @State private var isPaused = false
    @State private var timer: Timer?
    @State private var showingComplete = false
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

    // "Hold" for static stretches, "Move" for circular/dynamic ones
    private var actionLabel: String {
        guard let name = currentStretch?.name else { return "Hold" }
        let lower = name.lowercased()
        let dynamicKeywords = ["circle", "rotation", "swing", "roll", "dynamic",
                               "mobilit", "oscillat", "bounce", "pendulum", "windmill"]
        return dynamicKeywords.contains(where: { lower.contains($0) }) ? "Move" : "Hold"
    }

    private var sideLabel: String? {
        guard bothSidesMode && !isTransitioning && isPlaying else { return nil }
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

                    // Rep indicator
                    if repsPerStretch > 1 && isPlaying && !isTransitioning {
                        Text("Rep \(currentRep) of \(repsPerStretch)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

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
                            if bothSidesMode && !isTransitioning && isPlaying {
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
        .alert("Stretch Routine Complete!", isPresented: $showingComplete) {
            Button("Done") { dismiss() }
        } message: {
            let count = stretches.count
            let sideNote = bothSidesMode ? " (both sides)" : ""
            Text("You completed \(count) stretch\(count == 1 ? "" : "es")\(sideNote). Great work!")
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
    }

    private func togglePause() { isPaused.toggle() }

    private func skipCurrent() { advance() }

    private func advance() {
        // Not done with all reps → next rep
        if !isTransitioning && currentRep < repsPerStretch {
            currentRep += 1
            timeRemaining = holdDuration
            playFeedback(.start)
            return
        }

        // Transition done → start holding
        if isTransitioning {
            isTransitioning = false
            timeRemaining = holdDuration
            playFeedback(.start)
            return
        }

        // Finished all reps on first side → switch to second side
        if bothSidesMode && currentSide == 0 {
            currentSide = 1
            currentRep = 1
            timeRemaining = holdDuration
            playFeedback(.start)
            return
        }

        // Move to next stretch
        currentIndex += 1
        currentRep = 1
        currentSide = 0

        if currentIndex >= stretches.count {
            timer?.invalidate()
            timer = nil
            isPlaying = false
            playFeedback(.complete)
            showingComplete = true
            return
        }

        isTransitioning = true
        timeRemaining = Self.transitionDuration
        playFeedback(.start)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard !isPaused else { return }
            timeRemaining -= 1
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
}
