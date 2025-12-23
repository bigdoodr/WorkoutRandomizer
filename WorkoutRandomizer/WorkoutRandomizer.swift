import SwiftUI
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(AVKit)
import AVKit
#endif

private enum FeedbackEvent {
    case start
    case warning
    case end
}

@main
struct WorkoutGeneratorApp: App {
    var body: some Scene {
        WindowGroup {
            WorkoutGeneratorView()
        }
    }
}

struct Exercise {
    let name: String
    let videoPath: String?
}

struct WorkoutItem {
    let exercise: Exercise
    let isRest: Bool
    let duration: Int
}

struct WorkoutGeneratorView: View {
    @State private var selectedFocusAreas: Set<String> = ["Legs", "Core", "Cardio"]
    @State private var difficulty = "Expert/Advanced"
    @State private var totalDuration = 10
    @State private var exerciseDuration = 20
    @State private var restDuration = 10
    @State private var restEvery = 1
    @State private var generatedRoutine: [Exercise] = []
    @State private var showingWorkout = false
    @State private var isGenerating = false
    
    // Feedback settings
    @State private var enableSound_iOS_tv_vision = true
    @State private var enableHaptics_iOS_vision = true
    @State private var enableSound_macOS = true
    
    @StateObject private var videoManager = VideoManager.shared
    @AppStorage("videoMode") private var videoModeRaw: String = VideoMode.stream.rawValue
    @State private var showVideoModePrompt = false
    @State private var downloadProgress: (completed: Int, total: Int)? = nil
    
    let focusAreas = ["Chest", "Legs", "Legs, No Cardio", "Shoulders", "Triceps", "Glutes", "Core", "Core, No Cardio", "Cardio"]
    let difficulties = ["Beginner", "Medium", "Hard", "Expert/Advanced"]
    
    let exercises: [String: [String: [Exercise]]] = [
        "Chest": [
            "Beginner": [],
            "Medium": [Exercise(name: "Push-Ups", videoPath: "/resources/pushupsAngle2.mp4")],
            "Hard": [],
            "Expert/Advanced": [Exercise(name: "One-Legged Skier Push-Ups", videoPath: "/resources/onelegskierpushups.mp4")]
        ],
        "Legs": [
            "Beginner": [
                Exercise(name: "Squats", videoPath: "/resources/squats.mp4"),
                Exercise(name: "3-Way Lunges", videoPath: "/resources/3wayLungesAngle2.mp4")
            ],
            "Medium": [
                Exercise(name: "Alternating Split Squats", videoPath: "/resources/splitSquats.mp4"),
                Exercise(name: "Frog Hops", videoPath: "/resources/frogHops.mp4"),
                Exercise(name: "Squat Jumps", videoPath: "/resources/squatJumps.mp4")
            ],
            "Hard": [
                Exercise(name: "180° Squat Jumps", videoPath: "/resources/180JumpSquats.mp4"),
                Exercise(name: "Ninja Tuck Jumps", videoPath: "/resources/ninjaTuckJumps.mp4"),
                Exercise(name: "Prisoner Squat Jumps", videoPath: "/resources/prisonerSquatJumps.mp4"),
                Exercise(name: "3-Point Alternating Hops", videoPath: "/resources/3pointAltHops.mp4")
            ],
            "Expert/Advanced": [
                Exercise(name: "Prisoner Ninja Tuck Jumps", videoPath: "/resources/prisonerNinjaTuckJumps.mp4"),
                Exercise(name: "Triple Skyfalls", videoPath: "/resources/3xskyfalls.mp4")
            ]
        ],
        "Legs, No Cardio": [
            "Beginner": [Exercise(name: "Reverse Lunge to High Knee", videoPath: "/resources/reverseLungeHighKneeAngle2.mp4")]
        ],
        "Shoulders": [
            "Beginner": [],
            "Medium": [Exercise(name: "Pike Push-Ups", videoPath: "/resources/pikePushups.mp4")],
            "Hard": [Exercise(name: "Kneeling Spider-Man Push-Ups", videoPath: "/resources/kneelingSpidermanPushups.mp4")],
            "Expert/Advanced": [Exercise(name: "Spider-Man Push-Ups", videoPath: "/resources/spidermanPushups.mp4")]
        ],
        "Triceps": [
            "Beginner": [Exercise(name: "Bench Dips", videoPath: "/resources/benchDipsAngle1.mp4")]
        ],
        "Glutes": [
            "Beginner": [
                Exercise(name: "Bridges", videoPath: "/resources/bridgesAngle2.mp4"),
                Exercise(name: "Hip Bucks", videoPath: "/resources/hipBucks.mp4")
            ],
            "Medium": [Exercise(name: "Single Leg Hip Bucks", videoPath: "/resources/singleLegHipBucks.mp4")]
        ],
        "Core": [
            "Beginner": [
                Exercise(name: "Bear Taps", videoPath: "/resources/bearTapsAngle2.mp4"),
                Exercise(name: "Walking Marches", videoPath: "/resources/walkingMarches.mp4")
            ],
            "Medium": [
                Exercise(name: "Jackknives - Level 1", videoPath: "/resources/jackknivesLevel1.mp4"),
                Exercise(name: "Russian V-Twists", videoPath: "/resources/russianVTwistsAngle1.mp4"),
                Exercise(name: "Spider-Man Lunges", videoPath: "/resources/spidermanLungesAngle2.mp4")
            ],
            "Hard": [
                Exercise(name: "Bicycle Crunches", videoPath: "/resources/bicycleCrunchesAngle2.mp4"),
                Exercise(name: "Jackknives - Level 2", videoPath: "/resources/jackknivesLevel2.mp4"),
                Exercise(name: "Mountain Climbers", videoPath: "/resources/mountainClimbers.mp4"),
                Exercise(name: "Plank Elbow to Knee Taps", videoPath: "/resources/plankElbowToKneeTaps.mp4"),
                Exercise(name: "Side Kickthroughs", videoPath: "/resources/sideKickthroughs.mp4")
            ],
            "Expert/Advanced": [Exercise(name: "Twisting Piston Push-Ups", videoPath: "/resources/twistingPistonPushUps.mp4")]
        ],
        "Core, No Cardio": [
            "Beginner": [
                Exercise(name: "Ab-Roller", videoPath: "/resources/abRollerAngle1.mp4"),
                Exercise(name: "Bird Dogs", videoPath: "/resources/birdDogs.mp4"),
                Exercise(name: "Good Mornings", videoPath: "/resources/goodMorningsAngle2.mp4"),
                Exercise(name: "Swipers", videoPath: "/resources/swipersAngle2.mp4")
            ],
            "Medium": [
                Exercise(name: "Plank Elbow Ups", videoPath: "/resources/plankElbowUps.mp4"),
                Exercise(name: "Shoulder Taps", videoPath: "/resources/shoulderTapsAngle1.mp4")
            ]
        ],
        "Cardio": [
            "Beginner": [
                Exercise(name: "Jump/Air Rope", videoPath: "/resources/jumprope.mp4"),
                Exercise(name: "Shadow Boxing", videoPath: "/resources/shadowboxing.mp4"),
                Exercise(name: "Toe Taps", videoPath: "/resources/toeTaps.mp4")
            ],
            "Medium": [
                Exercise(name: "High Knees", videoPath: "/resources/highknees.mp4"),
                Exercise(name: "Jumping Jacks", videoPath: "/resources/jumpingjacks.mp4"),
                Exercise(name: "Skier Hops", videoPath: "/resources/skierhops.mp4")
            ]
        ]
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // View Exercises
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            // Navigate to the Exercises view
                        } label: {
                            NavigationLink(destination: ExercisesView(exercisesByArea: exercises)) {
                                HStack {
                                    Image(systemName: "list.bullet.rectangle.portrait")
                                    Text("View Exercises")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.purple)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    
                    // Focus Areas
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Focus Areas")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        HStack {
                            Toggle(isOn: Binding(
                                get: { selectedFocusAreas.count == focusAreas.count },
                                set: { newValue in
                                    if newValue {
                                        selectedFocusAreas = Set(focusAreas)
                                    } else {
                                        selectedFocusAreas.removeAll()
                                    }
                                }
                            )) {
                                Label("Select All", systemImage: selectedFocusAreas.count == focusAreas.count ? "checkmark.square.fill" : "square")
                            }
                            .toggleStyle(.switch)
                        }
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                            ForEach(focusAreas, id: \.self) { area in
                                HStack {
                                    Image(systemName: selectedFocusAreas.contains(area) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(selectedFocusAreas.contains(area) ? .blue : .secondary)
                                    Text(area)
                                        .font(.subheadline)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if selectedFocusAreas.contains(area) {
                                        selectedFocusAreas.remove(area)
                                    } else {
                                        selectedFocusAreas.insert(area)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Difficulty
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Difficulty")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        HStack(spacing: 15) {
                            ForEach(difficulties, id: \.self) { level in
                                HStack {
                                    Image(systemName: difficulty == level ? "circle.fill" : "circle")
                                        .foregroundStyle(difficulty == level ? .blue : .secondary)
                                    Text(level)
                                        .font(.subheadline)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    difficulty = level
                                }
                            }
                        }
                    }
                    
                    // Durations
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Durations")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        VStack(spacing: 15) {
                            HStack {
                                Text("Total Duration")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(totalDuration) min")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: Binding(
                                get: { Double(totalDuration) },
                                set: { totalDuration = Int($0) }
                            ), in: 1...120, step: 1) {
                                Text("Total Duration")
                            } minimumValueLabel: {
                                Image(systemName: "clock")
                            } maximumValueLabel: {
                                Image(systemName: "clock.fill")
                            }
                            
                            HStack {
                                Text("Exercise Duration")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(exerciseDuration) sec")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: Binding(
                                get: { Double(exerciseDuration) },
                                set: { exerciseDuration = Int($0) }
                            ), in: 1...120, step: 1) {
                                Text("Exercise Duration")
                            } minimumValueLabel: {
                                Image(systemName: "timer")
                            } maximumValueLabel: {
                                Image(systemName: "timer")
                            }
                            
                            HStack {
                                Text("Rest Duration")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(restDuration) sec")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: Binding(
                                get: { Double(restDuration) },
                                set: { restDuration = Int($0) }
                            ), in: 1...120, step: 1) {
                                Text("Rest Duration")
                            } minimumValueLabel: {
                                Image(systemName: "pause")
                            } maximumValueLabel: {
                                Image(systemName: "pause.fill")
                            }
                            
                            HStack {
                                Text("Rest Every Nth Exercises")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(restEvery)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: Binding(
                                get: { Double(restEvery) },
                                set: { restEvery = Int($0) }
                            ), in: 1...20, step: 1) {
                                Text("Rest Every Nth Exercises")
                            } minimumValueLabel: {
                                Image(systemName: "1.circle")
                            } maximumValueLabel: {
                                Image(systemName: "20.circle.fill")
                            }
                        }
                    }
                    
                    // Feedback Settings
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Feedback")
                            .font(.title2)
                            .fontWeight(.semibold)

                        VStack(spacing: 10) {
#if os(iOS) || os(tvOS) || os(visionOS)
                            Toggle(isOn: $enableSound_iOS_tv_vision) {
                                Label("Sounds (iOS/tvOS/visionOS)", systemImage: enableSound_iOS_tv_vision ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            }
#endif
#if os(iOS) || os(visionOS)
                            Toggle(isOn: $enableHaptics_iOS_vision) {
                                Label("Haptics (iOS/visionOS)", systemImage: enableHaptics_iOS_vision ? "hand.tap.fill" : "hand.raised")
                            }
#endif
#if os(macOS)
                            Toggle(isOn: $enableSound_macOS) {
                                Label("Sounds (macOS)", systemImage: enableSound_macOS ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            }
#endif
                        }
                    }
                    
                    // Video Options
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Video Options")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Picker("Video Mode", selection: $videoModeRaw) {
                            ForEach(VideoMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: videoModeRaw) { _, newValue in
                            videoManager.videoMode = newValue
                        }
                        
                        if VideoMode(rawValue: videoModeRaw) == .downloadOnFirstLaunch {
                            if let progress = downloadProgress {
                                Text("Downloading videos \(progress.completed) of \(progress.total)...")
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Download Videos") {
                                    startVideoDownload()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    
                    // Generate Button
                    Button {
                        generateWorkout()
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Generating workout...")
                            } else {
                                Text("Generate Workout")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(isGenerating || selectedFocusAreas.isEmpty)
                    
                    // Generated Routine
                    if !generatedRoutine.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Generated Routine")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(generatedRoutine.enumerated()), id: \.offset) { index, exercise in
                                    HStack {
                                        Text("\(index + 1).")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 30, alignment: .leading)
                                        Text(exercise.name)
                                            .font(.subheadline)
                                        Spacer()
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .padding()
                            .background(.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            
                            Button {
                                showingWorkout = true
                            } label: {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Start Workout")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.green)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Workout Generator")
        }
        .sheet(isPresented: $showingWorkout) {
            WorkoutPlayerView(
                routine: generatedRoutine,
                exerciseDuration: exerciseDuration,
                restDuration: restDuration,
                restEvery: restEvery,
                enableSound_iOS_tv_vision: enableSound_iOS_tv_vision,
                enableHaptics_iOS_vision: enableHaptics_iOS_vision,
                enableSound_macOS: enableSound_macOS
            )
        }
        .onAppear {
            if !videoManager.didPromptForVideoMode {
                showVideoModePrompt = true
            }
        }
        .confirmationDialog("Select Video Mode", isPresented: $showVideoModePrompt, titleVisibility: .visible) {
            Button(VideoMode.downloadOnFirstLaunch.rawValue) {
                videoModeRaw = VideoMode.downloadOnFirstLaunch.rawValue
                videoManager.videoMode = videoModeRaw
                videoManager.didPromptForVideoMode = true
                startVideoDownload()
            }
            Button(VideoMode.stream.rawValue) {
                videoModeRaw = VideoMode.stream.rawValue
                videoManager.videoMode = videoModeRaw
                videoManager.didPromptForVideoMode = true
            }
            Button(VideoMode.none.rawValue) {
                videoModeRaw = VideoMode.none.rawValue
                videoManager.videoMode = videoModeRaw
                videoManager.didPromptForVideoMode = true
            }
            Button("Cancel", role: .cancel) { }
        }
        .overlay(alignment: .center) {
            if let progress = downloadProgress {
                Color.black.opacity(0.4)
                    .cornerRadius(10)
                    .padding()
                    .overlay {
                        VStack(spacing: 20) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(1.5)
                            Text("Downloading videos \(progress.completed) of \(progress.total)")
                                .foregroundStyle(.white)
                                .font(.headline)
                            Button("Cancel") {
                                VideoManager.shared.cancelAllDownloads()
                                downloadProgress = nil
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                        .padding(30)
                    }
            }
        }
    }
    
    private func startVideoDownload() {
        // Gather keys for all exercises that have known videos in VideoManager
        let allKeys = exercises.values
            .flatMap { $0.values.flatMap { $0 } }
            .map { $0.name }
            .filter { VideoManager.shared.path(for: $0) != nil }
            .unique()

        downloadProgress = (completed: 0, total: allKeys.count)

        videoManager.downloadAll(keys: allKeys, progress: { completed, total in
            downloadProgress = (completed: completed, total: total)
        }, completion: {
            downloadProgress = nil
        })
    }
    
    private func generateWorkout() {
        isGenerating = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let allowedLevels = getAllowedLevels(for: difficulty)
            var pool: [Exercise] = []
            
            // Build exercise pool
            for area in selectedFocusAreas {
                for level in allowedLevels {
                    if let areaExercises = exercises[area],
                       let levelExercises = areaExercises[level] {
                        pool.append(contentsOf: levelExercises)
                    }
                }
            }
            
            guard !pool.isEmpty else {
                isGenerating = false
                return
            }
            
            // Calculate number of exercises needed
            let fullCycle = Double(exerciseDuration) + (Double(restDuration) / Double(restEvery))
            let totalSecs = Double(totalDuration) * 60
            let maxExercises = Int(ceil(totalSecs / fullCycle))
            
            // Create balanced routine
            let selected = createBalancedRoutine(from: pool, maxCount: maxExercises)
            
            // Build final routine with rests
            var routine: [Exercise] = []
            for (index, exercise) in selected.enumerated() {
                routine.append(exercise)
                if ((index + 1) % restEvery == 0) && (index != selected.count - 1) {
                    routine.append(Exercise(name: "Rest", videoPath: nil))
                }
            }
            
            generatedRoutine = routine
            isGenerating = false
        }
    }
    
    private func getAllowedLevels(for difficulty: String) -> [String] {
        switch difficulty {
        case "Beginner": return ["Beginner"]
        case "Medium": return ["Beginner", "Medium"]
        case "Hard": return ["Beginner", "Medium", "Hard"]
        case "Expert/Advanced": return ["Beginner", "Medium", "Hard", "Expert/Advanced"]
        default: return ["Beginner"]
        }
    }
    
    private func createBalancedRoutine(from pool: [Exercise], maxCount: Int) -> [Exercise] {
        let shuffled = pool.shuffled()
        var uniqueExercises: [Exercise] = []
        var seen = Set<String>()
        
        // Get unique exercises first
        for exercise in shuffled {
            if !seen.contains(exercise.name) && uniqueExercises.count < maxCount {
                uniqueExercises.append(exercise)
                seen.insert(exercise.name)
            }
        }
        
        // Fill remaining slots with repeats
        var result = uniqueExercises
        while result.count < maxCount {
            let reshuffled = uniqueExercises.shuffled()
            for exercise in reshuffled {
                if result.count < maxCount {
                    result.append(exercise)
                } else {
                    break
                }
            }
        }
        
        return result
    }
}

struct WorkoutPlayerView: View {
    let routine: [Exercise]
    let exerciseDuration: Int
    let restDuration: Int
    let restEvery: Int
    let enableSound_iOS_tv_vision: Bool
    let enableHaptics_iOS_vision: Bool
    let enableSound_macOS: Bool
    
    @State private var currentIndex = 0
    @State private var timeRemaining = 0
    @State private var isPlaying = false
    @State private var isPaused = false
    @State private var timer: Timer?
#if canImport(AVFoundation)
    @State private var audioEngine: AVAudioEngine?
    @State private var playerNode: AVAudioPlayerNode?
#endif
    @StateObject private var videoManager = VideoManager.shared
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
        guard let name = currentExercise?.name else { return nil }
        return videoManager.url(for: name)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Spacer()
                
                if VideoMode(rawValue: videoManager.videoMode) != Optional.none {
                    if let player = avPlayer {
                        VideoPlayer(player: player)
                            .frame(height: 220)
                            .cornerRadius(10)
                    } else if videoURL != nil {
                        // Placeholder until player prepared
                        Rectangle()
                            .fill(Color.black.opacity(0.1))
                            .frame(height: 220)
                            .cornerRadius(10)
                    }
                }
                
                // Exercise Name
                Text(currentExercise?.name ?? "Workout Complete")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                // Timer
                Text(timeRemaining > 0 ? "\(timeRemaining)" : "00")
                    .font(.system(size: 80, weight: .bold, design: .monospaced))
                    .foregroundStyle(timeRemaining <= 3 && timeRemaining > 0 ? .red : .primary)
                
                // Progress
                if currentIndex < routine.count {
                    Text("Exercise \(currentIndex + 1) of \(routine.count)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Controls
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
            .padding()
            .navigationTitle("Workout")
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
#if os(iOS) || os(visionOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        stopWorkout()
                        dismiss()
                    }
                }
#else
                ToolbarItem {
                    Button("Done") {
                        stopWorkout()
                        dismiss()
                    }
                }
#endif
            }
        }
        .onAppear {
            setupAudio()
            if let exercise = currentExercise {
                timeRemaining = exercise.name == "Rest" ? restDuration : exerciseDuration
            }
            prepareVideoForCurrentExercise(autoplay: false)
        }
        .onDisappear {
            stopWorkout()
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
        let playerItem = AVPlayerItem(url: url)
        let player = avPlayer ?? AVPlayer()
        player.replaceCurrentItem(with: playerItem)
        player.actionAtItemEnd = .none
        // Loop when the item ends
        playerEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { _ in
            player.seek(to: .zero)
            player.play()
        }
        avPlayer = player
        if autoplay { player.play() }
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
            // Also ensure mixer to output uses compatible format
            engine.connect(engine.mainMixerNode, to: output, format: hwFormat)
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
            }
        }
        return
#endif
#if canImport(AVFoundation)
    #if os(iOS) || os(tvOS) || os(visionOS)
        guard enableSound_iOS_tv_vision else { return }
        // Ensure session and engine are ready
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch { }

        if audioEngine == nil || playerNode == nil { setupAudio() }
        guard let engine = audioEngine else { return }
        let node: AVAudioPlayerNode
        if let existing = playerNode { node = existing } else {
            let newNode = AVAudioPlayerNode()
            engine.attach(newNode)
            engine.connect(newNode, to: engine.mainMixerNode, format: nil)
            playerNode = newNode
            node = newNode
        }
        if !engine.isRunning { try? engine.start() }

        // Choose tone by event
        let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        let sampleRate = mixerFormat.sampleRate
        let (frequency, duration): (Double, Double)
        switch event {
        case .start: frequency = 880; duration = 0.15 // A5 short
        case .warning: frequency = 1200; duration = 0.12 // higher quick chirp
        case .end: frequency = 523.25; duration = 0.25 // C5 longer
        }
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: mixerFormat, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        // Fill all channels consistently
        let channelCount = Int(mixerFormat.channelCount)
        for ch in 0..<channelCount {
            if let data = buffer.floatChannelData?[ch] {
                for i in 0..<Int(frameCount) {
                    let sample = sin(2.0 * Double.pi * frequency * Double(i) / sampleRate)
                    data[i] = Float(sample * 0.5)
                }
            }
        }
        node.scheduleBuffer(buffer, completionHandler: nil)
        if !node.isPlaying { node.play() }
    #endif
#endif
    }
    
    private func triggerHaptic(for event: FeedbackEvent) {
#if os(iOS) || os(visionOS)
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
        }
        _ = generator // keep reference in scope
        #endif
#endif
    }
    
    private func startWorkout() {
        isPlaying = true
        playFeedback(.start)
        prepareVideoForCurrentExercise(autoplay: true)
        startTimer()
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard !isPaused else { return }
            
            timeRemaining -= 1
            
            if timeRemaining == 3 {
                playFeedback(.warning) // Warning beep
            }
            
            if timeRemaining <= 0 {
                playFeedback(.end) // End beep
                nextExercise()
            }
        }
    }
    
    private func nextExercise() {
        currentIndex += 1
        
        if currentIndex >= routine.count {
            // Workout complete
            stopWorkout()
            return
        }
        
        let exercise = routine[currentIndex]
        timeRemaining = exercise.name == "Rest" ? restDuration : exerciseDuration
        prepareVideoForCurrentExercise(autoplay: true)
        playFeedback(.start) // Start beep for next exercise
    }
    
    private func togglePause() {
        isPaused.toggle()
        playFeedback(.warning)
        if isPaused { avPlayer?.pause() } else { avPlayer?.play() }
    }
    
    private func skipExercise() {
        playFeedback(.warning)
        nextExercise()
    }
    
    private func stopWorkout() {
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
    }
}
// MARK: - Array Unique Extension
fileprivate extension Array where Element: Hashable {
    func unique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

