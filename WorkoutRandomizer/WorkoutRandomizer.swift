import SwiftUI
internal import UniformTypeIdentifiers
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
import AVFoundation

struct AVPlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerContainerView, context: Context) {
        // Keep the player current and ensure layout updates
        if nsView.playerLayer.player !== player {
            nsView.playerLayer.player = player
        }
        nsView.needsLayout = true
        nsView.layoutSubtreeIfNeeded()
    }
}

final class PlayerContainerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = CALayer()
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
#endif

enum FeedbackEvent {
    case start
    case warning
    case end
    case complete
}

@main
struct WorkoutGeneratorApp: App {
    init() {
#if canImport(AVFoundation)
    #if os(iOS) || os(tvOS) || os(visionOS)
        Task.detached {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
            } catch {
                // Ignore configuration errors; we'll try again when needed
            }
        }
    #endif
#endif
#if os(iOS)
        // Activate WatchConnectivity session early so it's ready when needed
        _ = WorkoutConnectivityManager.shared
#endif
    }
    
    var body: some Scene {
        WindowGroup {
            WorkoutGeneratorView()
        }
    }
}

struct Exercise {
    let name: String
    let videoPath: String?
    let equipment: [String]
    var singleSided: Bool = false
}

enum TimerStyle: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case pyramid = "Pyramid"
    case blocks = "Repeating Blocks"
    var id: String { rawValue }
}

struct RepeatingBlocksConfig: Equatable {
    let exercisesPerBlock: Int
    let blockDurations: [Int]   // work seconds per block; rest = same
}

enum WorkoutIntention: String, CaseIterable, Identifiable {
    case generalFitness = "General Fitness"
    case fatBurn = "Fat Burn"
    case cardioEndurance = "Cardio Endurance"
    case strengthPower = "Strength / Power"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .generalFitness: return "star"
        case .fatBurn: return "flame"
        case .cardioEndurance: return "heart"
        case .strengthPower: return "bolt"
        }
    }

    var bannerColor: Color {
        switch self {
        case .generalFitness: return .green
        case .fatBurn: return .orange
        case .cardioEndurance: return .red
        case .strengthPower: return .blue
        }
    }

    func tip(for zone: String) -> String {
        switch (self, zone) {
        case (.fatBurn, "Zone 1"): return "Low intensity — light fat burn."
        case (.fatBurn, "Zone 2"): return "Optimal fat-oxidation zone."
        case (.fatBurn, "Zone 3"): return "Mixed fuel — fat + carbs."
        case (.fatBurn, "Zone 4"): return "Carb-dominant. EPOC effect boosts fat loss post-workout."
        case (.fatBurn, "Zone 5"): return "Max effort — significant afterburn effect."
        case (.cardioEndurance, "Zone 1"): return "Recovery pace. Push to Zone 2+ for gains."
        case (.cardioEndurance, "Zone 2"): return "Builds aerobic base efficiently."
        case (.cardioEndurance, "Zone 3"): return "Threshold training. Good for endurance."
        case (.cardioEndurance, "Zone 4"): return "Increases VO₂ max. Key zone for endurance gains."
        case (.cardioEndurance, "Zone 5"): return "Peak capacity. Use for short intervals."
        case (.strengthPower, "Zone 1"): return "Active recovery between sets."
        case (.strengthPower, "Zone 2"): return "Steady circuit pace."
        case (.strengthPower, "Zone 3"): return "Good for circuit-style strength work."
        case (.strengthPower, "Zone 4"): return "Power endurance territory."
        case (.strengthPower, "Zone 5"): return "Explosive power output. Great for HIIT."
        case (.generalFitness, "Zone 1"): return "Good for warm-up or cool-down."
        case (.generalFitness, "Zone 2"): return "Steady-state cardio zone."
        case (.generalFitness, "Zone 3"): return "Moderate effort. Good overall fitness."
        case (.generalFitness, "Zone 4"): return "High intensity. Improving fitness quickly."
        default: return "Max effort. Use sparingly."
        }
    }
}

struct UserExercise: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var focusArea: String
    var difficulty: String
}

@MainActor
@Observable
final class CustomExerciseStore {
    static let shared = CustomExerciseStore()
    private static let storageKey = "customExercises_v1"

    var exercises: [UserExercise] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([UserExercise].self, from: data) {
            exercises = decoded
        }
    }

    func add(_ exercise: UserExercise) {
        exercises.append(exercise)
        persist()
    }

    func remove(at offsets: IndexSet) {
        exercises.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(exercises) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

struct WorkoutItem {
    let exercise: Exercise
    let isRest: Bool
    let duration: Int
}

// MARK: - Import/Export Models
struct ExportableExercise: Codable, Identifiable {
    let id: String
    let name: String
    let isTimeBased: Bool
    let exerciseDuration: Int
    let restDuration: Int
    let sets: Int
    
    init(id: String = UUID().uuidString, name: String, isTimeBased: Bool, exerciseDuration: Int, restDuration: Int, sets: Int) {
        self.id = id
        self.name = name
        self.isTimeBased = isTimeBased
        self.exerciseDuration = exerciseDuration
        self.restDuration = restDuration
        self.sets = sets
    }
}

struct WorkoutDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var exercises: [ExportableExercise]
    
    init(exercises: [ExportableExercise]) {
        self.exercises = exercises
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        exercises = try JSONDecoder().decode([ExportableExercise].self, from: data)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(exercises)
        return FileWrapper(regularFileWithContents: data)
    }
}

struct WorkoutGeneratorView: View {
    @State private var selectedFocusAreas: Set<String> = []
    @State private var difficulty = "Expert/Advanced"
    @State private var totalDuration = 10
    @State private var exerciseDuration = 20
    @State private var restDuration = 10
    @State private var restEvery = 1
    @State private var generatedRoutine: [Exercise] = []
    @State private var showingWorkout = false
    @State private var isGenerating = false
    @State private var scrollToGeneratedToken = UUID()
    @State private var showingImportExport = false
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var exportDocument: WorkoutDocument?
    
    // Feedback settings
    @State private var enableSound_iOS_tv_vision = true
    @State private var enableHaptics_iOS_vision = true
    @State private var enableSound_macOS = true
    
    @State private var selectedEquipment: Set<String> = ["None"]
    @State private var timerStyle: TimerStyle = .standard
    @State private var selectedIntention: WorkoutIntention = .generalFitness
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
    @AppStorage("useAdvancedView") private var useAdvancedView = false
    @State private var showingTutorial = false
    @State private var customExerciseStore = CustomExerciseStore.shared
    @State private var showCustomTimers = false
    @State private var exerciseDurationOverrides: [Int: Int] = [:]
    @State private var showSaveConfirmation = false

    @StateObject private var videoManager = VideoManager.shared
    @State private var catalog = ExerciseCatalog.shared
    @AppStorage("videoMode") private var videoModeRaw: String = VideoMode.stream.rawValue
    @State private var showVideoModePrompt = false
    @State private var downloadProgress: (completed: Int, total: Int)? = nil
    
    var focusAreas: [String] { catalog.focusAreas }
    var difficulties: [String] { catalog.difficulties }
    var exercises: [String: [String: [Exercise]]] { catalog.exercises }
    private var allEquipmentOptions: [String] { ["None", "Ab Roller", "Chair/Box/Bench"] }

    private static let stretchKeywords = ["Stretch", "Recovery", "Cool Down", "Warm-Up"]
    var workoutFocusAreas: [String] {
        focusAreas.filter { area in
            !Self.stretchKeywords.contains { area.contains($0) }
        }
    }

    private struct QuickFilter {
        let label: String
        let icon: String
        let keywordsAny: [String]
        let keywordsExclude: [String]
        let color: Color
        func areas(_ all: [String]) -> Set<String> {
            Set(all.filter { a in
                let lower = a.lowercased()
                return keywordsAny.contains { lower.contains($0) }
                    && !keywordsExclude.contains { lower.contains($0) }
            })
        }
    }

    private var quickFilters: [QuickFilter] {
        [
            // "All" matched via special-case toggle logic
            QuickFilter(label: "All", icon: "figure.mixed.cardio",
                        keywordsAny: workoutFocusAreas.map { $0.lowercased() }, keywordsExclude: [], color: .blue),
            // Cardio = every area EXCEPT those explicitly marked "No Cardio"
            QuickFilter(label: "Cardio", icon: "heart.fill",
                        keywordsAny: workoutFocusAreas.map { $0.lowercased() }, keywordsExclude: ["no cardio"], color: .red),
            QuickFilter(label: "Core", icon: "figure.core.training",
                        keywordsAny: ["core"], keywordsExclude: [], color: .orange),
            QuickFilter(label: "Upper", icon: "figure.arms.open",
                        keywordsAny: ["upper", "arm", "shoulder", "chest", "back", "tricep", "bicep"], keywordsExclude: [], color: .purple),
            QuickFilter(label: "Lower", icon: "figure.walk",
                        keywordsAny: ["leg", "lower", "glute", "squat", "hip"], keywordsExclude: [], color: .green),
        ]
    }

    private func isFilterActive(_ filter: QuickFilter) -> Bool {
        let areas = filter.areas(workoutFocusAreas)
        if filter.label == "All" { return selectedFocusAreas.count == workoutFocusAreas.count }
        return !areas.isEmpty && areas.isSubset(of: selectedFocusAreas)
    }

    private func toggleFilter(_ filter: QuickFilter) {
        let areas = filter.areas(workoutFocusAreas)
        if filter.label == "All" {
            selectedFocusAreas = selectedFocusAreas.count == workoutFocusAreas.count
                ? [] : Set(workoutFocusAreas)
        } else if areas.isSubset(of: selectedFocusAreas) {
            selectedFocusAreas.subtract(areas)
        } else {
            selectedFocusAreas.formUnion(areas)
        }
    }

    private func equipmentIcon(_ item: String) -> String {
        switch item {
        case "None": return "nosign"
        case "Ab Roller": return "circle.dotted.circle"
        default: return "chair"
        }
    }

    private func equipmentLabel(_ item: String) -> String {
        switch item {
        case "Chair/Box/Bench": return "Chair / Box"
        default: return item
        }
    }

#if os(macOS)
    private var platformBackgroundColor: NSColor { .windowBackgroundColor }
#else
    private var platformBackgroundColor: UIColor { .systemBackground }
#endif

    @ViewBuilder
    private var focusAreaFilterRow: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickFilters, id: \.label) { filter in
                        Button { toggleFilter(filter) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: filter.icon)
                                Text(filter.label)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(isFilterActive(filter) ? filter.color : Color.gray.opacity(0.15))
                            .foregroundStyle(isFilterActive(filter) ? .white : .primary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
                .padding(.trailing, 24)
            }
            LinearGradient(
                colors: [.clear, Color(platformBackgroundColor)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 36)
            .allowsHitTesting(false)
        }
    }

    // Repeating Blocks state
    @State private var blocksCount: Int = 3
    @State private var exercisesPerBlock: Int = 3
    @State private var blockDurations: [Int] = [30, 25, 45]
    @State private var blocksTotalSets: Int = 2
    @State private var shuffleBlockSets: Bool = false

    var blocksSuperSetSeconds: Int {
        blockDurations.reduce(0) { $0 + exercisesPerBlock * $1 * 2 }
    }
    var blocksAvailableTotalSets: [Int] {
        let superSetSec = blocksSuperSetSeconds
        guard superSetSec > 0 else { return [1] }
        var options: [Int] = []
        var n = 1
        while n * superSetSec <= 90 * 60 { options.append(n); n += 1 }
        return options.isEmpty ? [1] : options
    }
    var blocksTotalSeconds: Int { blocksTotalSets * blocksSuperSetSeconds }

    private func clampBlocksTotalSets() {
        let options = blocksAvailableTotalSets
        if !options.contains(blocksTotalSets) { blocksTotalSets = options.first ?? 1 }
    }
    private func formatBlockTime(_ seconds: Int) -> String {
        let m = seconds / 60; let s = seconds % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // View Exercises / My Exercises
                        HStack(spacing: 10) {
                            NavigationLink(destination: ExercisesView(exercisesByArea: exercises)) {
                                HStack {
                                    Image(systemName: "list.bullet.rectangle.portrait")
                                    Text("All Exercises")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.purple)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            NavigationLink(destination: MyExercisesView(
                                focusAreas: focusAreas,
                                difficulties: difficulties
                            )) {
                                HStack {
                                    Image(systemName: "person.badge.plus")
                                    Text("My Exercises")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.indigo)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }

                        HStack(spacing: 10) {
                            NavigationLink(destination: StretchRoutineView()) {
                                HStack {
                                    Image(systemName: "figure.cooldown")
                                    Text("Stretch Routine")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.teal)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            NavigationLink(destination: SavedRoutinesView()) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                    Text("Saved Routines")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.brown)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        
                        // Basic/Advanced mode label
                        if !useAdvancedView {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Tap \(Image(systemName: "slider.horizontal.3")) for advanced options")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Focus Areas
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Focus Areas")
                                .font(.title2)
                                .fontWeight(.semibold)

                            // Quick filters — multi-select: tap to toggle each group
                            focusAreaFilterRow

                        }

                        // Equipment Available
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Equipment Available")
                                .font(.title2)
                                .fontWeight(.semibold)

                            HStack(spacing: 10) {
                                ForEach(allEquipmentOptions, id: \.self) { item in
                                    Button {
                                        if selectedEquipment.contains(item) {
                                            selectedEquipment.remove(item)
                                        } else {
                                            selectedEquipment.insert(item)
                                        }
                                    } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: equipmentIcon(item))
                                                .font(.title2)
                                            Text(equipmentLabel(item))
                                                .font(.caption2)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(selectedEquipment.contains(item) ? Color.blue : Color.gray.opacity(0.1))
                                        .foregroundStyle(selectedEquipment.contains(item) ? .white : .primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
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

                        // Intention — single-select icon chips
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Intention")
                                .font(.title2)
                                .fontWeight(.semibold)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 10) {
                                ForEach(WorkoutIntention.allCases) { intent in
                                    Button { selectedIntention = intent } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: intent.icon)
                                                .font(.title2)
                                            Text(intent.rawValue)
                                                .font(.caption)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(selectedIntention == intent ? intent.bannerColor : Color.gray.opacity(0.1))
                                        .foregroundStyle(selectedIntention == intent ? .white : .primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Timer Style — Standard always visible; Pyramid + Blocks advanced only
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Timer Style")
                                .font(.title2)
                                .fontWeight(.semibold)

                            HStack(spacing: 15) {
                                ForEach(useAdvancedView ? TimerStyle.allCases : [TimerStyle.standard]) { style in
                                    HStack {
                                        Image(systemName: timerStyle == style ? "circle.fill" : "circle")
                                            .foregroundStyle(timerStyle == style ? .blue : .secondary)
                                        Text(style.rawValue)
                                            .font(.subheadline)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture { timerStyle = style }
                                }
                            }

                            if timerStyle == .pyramid && useAdvancedView {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Pyramid cycle repeats to fill total duration — each round shares work & rest:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    ForEach(["30s work + 30s rest", "40s work + 40s rest", "50s work + 50s rest",
                                             "50s work + 50s rest", "40s work + 40s rest", "30s work + 30s rest"], id: \.self) { label in
                                        Text("• \(label)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(10)
                                .background(.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }

                        // Durations — preset chips
                        if timerStyle == .standard || timerStyle == .pyramid {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Durations")
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                VStack(alignment: .leading, spacing: 14) {
                                    // Total Duration presets
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Total Duration")
                                            .font(.subheadline)
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                ForEach([5, 10, 20, 30, 45, 60, 90], id: \.self) { preset in
                                                    Button { totalDuration = preset } label: {
                                                        Text("\(preset) min")
                                                            .font(.subheadline)
                                                            .padding(.horizontal, 14)
                                                            .padding(.vertical, 8)
                                                            .background(totalDuration == preset ? Color.blue : Color.gray.opacity(0.12))
                                                            .foregroundStyle(totalDuration == preset ? .white : .primary)
                                                            .clipShape(Capsule())
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            .padding(.horizontal, 2)
                                        }
                                    }

                                    if timerStyle == .standard {
                                        // Exercise Duration presets
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Exercise Duration")
                                                .font(.subheadline)
                                            HStack(spacing: 8) {
                                                ForEach([20, 30, 45, 60], id: \.self) { preset in
                                                    Button { exerciseDuration = preset } label: {
                                                        Text("\(preset)s")
                                                            .font(.subheadline)
                                                            .padding(.horizontal, 16)
                                                            .padding(.vertical, 8)
                                                            .background(exerciseDuration == preset ? Color.blue : Color.gray.opacity(0.12))
                                                            .foregroundStyle(exerciseDuration == preset ? .white : .primary)
                                                            .clipShape(Capsule())
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                                Spacer()
                                            }
                                        }

                                        // Rest Duration presets
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Rest Duration")
                                                .font(.subheadline)
                                            HStack(spacing: 8) {
                                                ForEach([10, 15, 30, 60], id: \.self) { preset in
                                                    Button { restDuration = preset } label: {
                                                        Text("\(preset)s")
                                                            .font(.subheadline)
                                                            .padding(.horizontal, 16)
                                                            .padding(.vertical, 8)
                                                            .background(restDuration == preset ? Color.blue : Color.gray.opacity(0.12))
                                                            .foregroundStyle(restDuration == preset ? .white : .primary)
                                                            .clipShape(Capsule())
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                                Spacer()
                                            }
                                        }

                                        // Rest Frequency — exercises per circuit before rest
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text("Rest Frequency")
                                                    .font(.subheadline)
                                                Spacer()
                                                Text(restEvery == 1 ? "After each" : "Every \(restEvery)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            HStack(spacing: 8) {
                                                ForEach([1, 2, 3, 4, 5], id: \.self) { n in
                                                    Button { restEvery = n } label: {
                                                        Text("\(n)")
                                                            .font(.subheadline)
                                                            .fontWeight(.medium)
                                                            .frame(width: 44, height: 36)
                                                            .background(restEvery == n ? Color.blue : Color.gray.opacity(0.12))
                                                            .foregroundStyle(restEvery == n ? .white : .primary)
                                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                                Spacer()
                                            }
                                            Text("Exercises before each rest break")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }

                        // Advanced only: Repeating Blocks config, Feedback, Video Options
                        if useAdvancedView {

                        // Repeating Blocks Configuration
                        if timerStyle == .blocks {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Block Configuration")
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                VStack(spacing: 15) {
                                    // Number of blocks
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Number of Blocks")
                                            .font(.subheadline)
                                        HStack(spacing: 16) {
                                            ForEach([2, 3, 4], id: \.self) { n in
                                                HStack(spacing: 4) {
                                                    Image(systemName: blocksCount == n ? "circle.fill" : "circle")
                                                        .foregroundStyle(blocksCount == n ? .blue : .secondary)
                                                    Text("\(n)")
                                                        .font(.subheadline)
                                                }
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    let presets = [30, 40, 50, 60]
                                                    blocksCount = n
                                                    blockDurations = (0..<n).map { i in
                                                        blockDurations.indices.contains(i) ? blockDurations[i] : presets[i % presets.count]
                                                    }
                                                    clampBlocksTotalSets()
                                                }
                                            }
                                        }
                                    }

                                    // Exercises per block
                                    HStack {
                                        Text("Exercises per Block")
                                            .font(.subheadline)
                                        Spacer()
                                        Stepper(value: $exercisesPerBlock, in: 2...5) {
                                            EmptyView()
                                        }
                                        .labelsHidden()
                                        .onChange(of: exercisesPerBlock) { _, _ in clampBlocksTotalSets() }
                                        Text("\(exercisesPerBlock)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .frame(minWidth: 24, alignment: .trailing)
                                    }

                                    // Per-block work durations
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Work Duration per Block (rest = same)")
                                            .font(.subheadline)
                                        let durationPresets = [20, 25, 30, 35, 40, 45, 50, 60]
                                        ForEach(0..<blocksCount, id: \.self) { i in
                                            HStack {
                                                Text("Block \(i + 1)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 55, alignment: .leading)
                                                Picker("Block \(i + 1)", selection: Binding(
                                                    get: { blockDurations.indices.contains(i) ? blockDurations[i] : 30 },
                                                    set: { newVal in
                                                        var updated = blockDurations
                                                        if updated.indices.contains(i) { updated[i] = newVal }
                                                        blockDurations = updated
                                                        clampBlocksTotalSets()
                                                    }
                                                )) {
                                                    ForEach(durationPresets, id: \.self) { s in
                                                        Text("\(s)s").tag(s)
                                                    }
                                                }
                                                .pickerStyle(.segmented)
                                            }
                                        }
                                    }

                                    // Total workout picker
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("Total Workout")
                                                .font(.subheadline)
                                            Spacer()
                                            Text(formatBlockTime(blocksTotalSeconds))
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        Picker("Total Workout", selection: $blocksTotalSets) {
                                            ForEach(blocksAvailableTotalSets, id: \.self) { n in
                                                Text("\(n)× cycle · \(formatBlockTime(n * blocksSuperSetSeconds))")
                                                    .tag(n)
                                            }
                                        }
                                        #if os(iOS)
                                        .pickerStyle(.wheel)
                                        .frame(height: 100)
                                        #endif
                                    }

                                    // Shuffle option (only meaningful when sets > 1)
                                    if blocksTotalSets > 1 {
                                        Toggle(isOn: $shuffleBlockSets) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Shuffle order each set")
                                                    .font(.subheadline)
                                                Text("Re-randomize exercise order every cycle")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
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
#if os(iOS)
                                Toggle(isOn: $enableHaptics_iOS_vision) {
                                    Label("Haptics (iOS)", systemImage: enableHaptics_iOS_vision ? "hand.tap.fill" : "hand.raised")
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
                        
                        } // end if useAdvancedView

                        // Generate Button
                        Button {
                            generateWorkout()
                            // Attempt to auto-scroll to the generated section after state updates
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation {
                                    proxy.scrollTo(scrollToGeneratedToken, anchor: .top)
                                }
                            }
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
                        
                        if !generatedRoutine.isEmpty {
                            Text("Workout generated below")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        
                        // Generated Routine
                        if !generatedRoutine.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Generated Routine")
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    if useAdvancedView {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                showCustomTimers.toggle()
                                                if !showCustomTimers { exerciseDurationOverrides.removeAll() }
                                            }
                                        } label: {
                                            Label(showCustomTimers ? "Timers On" : "Custom Timers",
                                                  systemImage: showCustomTimers ? "timer.circle.fill" : "timer.circle")
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(showCustomTimers ? Color.blue : Color.gray.opacity(0.15))
                                                .foregroundStyle(showCustomTimers ? .white : .primary)
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

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
                                            if showCustomTimers && exercise.name != "Rest" {
                                                HStack(spacing: 4) {
                                                    Text("\(exerciseDurationOverrides[index] ?? exerciseDuration)s")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .frame(minWidth: 32, alignment: .trailing)
                                                    Stepper(
                                                        value: Binding(
                                                            get: { exerciseDurationOverrides[index] ?? exerciseDuration },
                                                            set: { exerciseDurationOverrides[index] = $0 }
                                                        ),
                                                        in: 5...300, step: 5
                                                    ) { EmptyView() }
                                                    .labelsHidden()
                                                }
                                            } else if showCustomTimers && exercise.name == "Rest" {
                                                HStack(spacing: 4) {
                                                    Text("\(exerciseDurationOverrides[index] ?? restDuration)s")
                                                        .font(.caption)
                                                        .foregroundStyle(.blue)
                                                        .frame(minWidth: 32, alignment: .trailing)
                                                    Stepper(
                                                        value: Binding(
                                                            get: { exerciseDurationOverrides[index] ?? restDuration },
                                                            set: { exerciseDurationOverrides[index] = $0 }
                                                        ),
                                                        in: 5...300, step: 5
                                                    ) { EmptyView() }
                                                    .labelsHidden()
                                                }
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                                .padding()
                                .background(.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                
                                VStack(spacing: 8) {
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

                                    HStack(spacing: 8) {
                                        Button {
                                            exportWorkout()
                                        } label: {
                                            HStack {
                                                Image(systemName: "square.and.arrow.up")
                                                Text("Export")
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(.blue)
                                            .foregroundStyle(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                        }

                                        Button {
                                            saveGeneratedRoutine()
                                        } label: {
                                            HStack {
                                                Image(systemName: "bookmark.fill")
                                                Text("Save")
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(.purple)
                                            .foregroundStyle(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                    }
                                }
                            }
                            .id(scrollToGeneratedToken)
                        }
                        
                        // Import Workout Button
                        if generatedRoutine.isEmpty {
                            Button {
                                showingImporter = true
                            } label: {
                                HStack {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Import Workout")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.purple)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Workout Generator")
            .toolbar {
#if os(iOS) || os(visionOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { useAdvancedView.toggle() }
                    } label: {
                        Label(useAdvancedView ? "Basic" : "Advanced",
                              systemImage: useAdvancedView ? "slider.horizontal.below.square.and.square.filled" : "slider.horizontal.3")
                            .labelStyle(.iconOnly)
                    }
                }
#else
                ToolbarItem {
                    Button { withAnimation { useAdvancedView.toggle() } } label: {
                        Label(useAdvancedView ? "Basic" : "Advanced",
                              systemImage: useAdvancedView ? "slider.horizontal.below.square.and.square.filled" : "slider.horizontal.3")
                    }
                }
#endif
            }
        }
        .onChange(of: useAdvancedView) { _, newValue in
            if !newValue && timerStyle != .standard {
                timerStyle = .standard
            }
        }
        .sheet(isPresented: $showingWorkout) {
            WorkoutPlayerView(
                routine: generatedRoutine,
                exerciseDuration: exerciseDuration,
                restDuration: restDuration,
                restEvery: restEvery,
                timerStyle: timerStyle,
                intention: selectedIntention,
                blocksConfig: timerStyle == .blocks ? RepeatingBlocksConfig(exercisesPerBlock: exercisesPerBlock, blockDurations: blockDurations) : nil,
                enableSound_iOS_tv_vision: enableSound_iOS_tv_vision,
                enableHaptics_iOS_vision: enableHaptics_iOS_vision,
                enableSound_macOS: enableSound_macOS,
                durationOverrides: exerciseDurationOverrides.isEmpty ? nil : exerciseDurationOverrides
            )
        }
        .sheet(isPresented: $showingTutorial) {
            TutorialView()
        }
        .alert("Routine Saved", isPresented: $showSaveConfirmation) {
            Button("OK") { }
        } message: {
            Text("This workout has been added to My Routines in the Saved Routines tab.")
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "workout.json",
            onCompletion: { result in
                switch result {
                case .success(let url):
                    print("Workout exported to: \(url)")
                case .failure(let error):
                    print("Export failed: \(error.localizedDescription)")
                }
                exportDocument = nil
            }
        )
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                do {
                    let data = try Data(contentsOf: url)
                    let exercises = try JSONDecoder().decode([ExportableExercise].self, from: data)
                    let document = WorkoutDocument(exercises: exercises)
                    importWorkout(from: document)
                } catch {
                    print("Import failed: \(error.localizedDescription)")
                }
            case .failure(let error):
                print("File selection failed: \(error.localizedDescription)")
            }
        }
        .onAppear {
            if !videoManager.didPromptForVideoMode {
                showVideoModePrompt = true
            }
            if !hasSeenTutorial {
                showingTutorial = true
            }
        }
        .task {
            await catalog.refresh()
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

            // Build exercise pool, filtered by selected equipment
            for area in selectedFocusAreas {
                for level in allowedLevels {
                    if let areaExercises = exercises[area],
                       let levelExercises = areaExercises[level] {
                        let available = levelExercises.filter { ex in
                            ex.equipment.contains { selectedEquipment.contains($0) }
                        }
                        pool.append(contentsOf: available)
                    }
                }
            }

            // Merge user-defined custom exercises
            for custom in customExerciseStore.exercises {
                if selectedFocusAreas.contains(custom.focusArea) && allowedLevels.contains(custom.difficulty) && selectedEquipment.contains("None") {
                    pool.append(Exercise(name: custom.name, videoPath: nil, equipment: ["None"]))
                }
            }

            guard !pool.isEmpty else {
                isGenerating = false
                return
            }

            // Compute target exercise count based on timer style
            let pyramidCycleSecs = WorkoutPlayerView.pyramidIntervals.reduce(0) { $0 + $1.work + $1.rest }
            let maxExercises: Int
            switch timerStyle {
            case .pyramid:
                let cycles = max(1, Int(ceil(Double(totalDuration) * 60.0 / Double(pyramidCycleSecs))))
                maxExercises = cycles * WorkoutPlayerView.pyramidIntervals.count
            case .blocks:
                maxExercises = blocksTotalSets * blocksCount * exercisesPerBlock
            case .standard:
                let fullCycle = Double(exerciseDuration) + (Double(restDuration) / Double(restEvery))
                let totalSecs = Double(totalDuration) * 60
                maxExercises = Int(ceil(totalSecs / fullCycle))
            }

            // Create balanced routine
            let selected = createBalancedRoutine(from: pool, maxCount: maxExercises)

            // Build final routine with rests
            var routine: [Exercise] = []
            if timerStyle == .pyramid || timerStyle == .blocks {
                // For blocks with shuffle: divide exercises into sets and shuffle each independently
                let exercises: [Exercise]
                if timerStyle == .blocks && shuffleBlockSets && blocksTotalSets > 1 {
                    let setSize = blocksCount * exercisesPerBlock
                    let basePool = Array(selected.prefix(setSize))
                    var shuffled: [Exercise] = []
                    for _ in 0..<blocksTotalSets {
                        shuffled.append(contentsOf: basePool.shuffled())
                    }
                    exercises = shuffled
                } else {
                    exercises = selected
                }
                // Every exercise gets its own rest (except the last)
                for (index, exercise) in exercises.enumerated() {
                    routine.append(exercise)
                    if index < exercises.count - 1 {
                        routine.append(Exercise(name: "Rest", videoPath: nil, equipment: ["None"]))
                    }
                }
            } else {
                for (index, exercise) in selected.enumerated() {
                    routine.append(exercise)
                    if ((index + 1) % restEvery == 0) && (index != selected.count - 1) {
                        routine.append(Exercise(name: "Rest", videoPath: nil, equipment: ["None"]))
                    }
                }
            }

            generatedRoutine = routine
            exerciseDurationOverrides.removeAll()
            showCustomTimers = false
            isGenerating = false
            scrollToGeneratedToken = UUID()
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
    
    private func exportWorkout() {
        let exportableExercises = generatedRoutine.map { exercise in
            ExportableExercise(
                name: exercise.name,
                isTimeBased: true,
                exerciseDuration: exercise.name == "Rest" ? restDuration : exerciseDuration,
                restDuration: exercise.name == "Rest" ? 0 : restDuration,
                sets: 1
            )
        }
        let document = WorkoutDocument(exercises: exportableExercises)
        exportDocument = document
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showingExporter = true
        }
    }
    
    private func saveGeneratedRoutine() {
        var savedExercises: [SavedRoutineExercise] = []
        for (i, ex) in generatedRoutine.enumerated() {
            if ex.name == "Rest" {
                let restDur = exerciseDurationOverrides[i] ?? restDuration
                if !savedExercises.isEmpty {
                    let last = savedExercises[savedExercises.count - 1]
                    savedExercises[savedExercises.count - 1] = SavedRoutineExercise(
                        name: last.name,
                        duration: last.duration,
                        restDuration: restDur,
                        singleSided: last.singleSided,
                        moveType: last.moveType
                    )
                }
            } else {
                let dur = exerciseDurationOverrides[i] ?? exerciseDuration
                savedExercises.append(SavedRoutineExercise(
                    name: ex.name,
                    duration: dur,
                    restDuration: 0,
                    singleSided: ex.singleSided,
                    moveType: .move
                ))
            }
        }
        let focusLabel = selectedFocusAreas.sorted().prefix(2).joined(separator: " & ")
        let routineName = focusLabel.isEmpty ? "My Workout" : "\(focusLabel) Workout"
        let routine = SavedWorkoutRoutine(
            name: routineName,
            routineDescription: "",
            source: "My Routines",
            sourceURL: "",
            exercises: savedExercises,
            accentColorName: "purple",
            systemImage: "dumbbell.fill"
        )
        SavedRoutineStore.shared.save(routine)
        showSaveConfirmation = true
    }

    private func importWorkout(from document: WorkoutDocument) {
        var importedRoutine: [Exercise] = []
        var didSetDurations = false
        
        for exportableExercise in document.exercises {
            // Try to find matching exercise in our database
            var foundExercise: Exercise?
            
            for (_, difficultyDict) in exercises {
                for (_, exerciseList) in difficultyDict {
                    if let match = exerciseList.first(where: { $0.name == exportableExercise.name }) {
                        foundExercise = match
                        break
                    }
                }
                if foundExercise != nil { break }
            }
            
            // If found, use it; otherwise create a basic exercise with no video
            let exercise = foundExercise ?? Exercise(name: exportableExercise.name, videoPath: nil, equipment: ["None"])
            importedRoutine.append(exercise)
            
            // Update durations from the first non-rest exercise only
            if !didSetDurations && exportableExercise.isTimeBased && exportableExercise.name != "Rest" {
                exerciseDuration = exportableExercise.exerciseDuration
                if exportableExercise.restDuration > 0 {
                    restDuration = exportableExercise.restDuration
                }
                didSetDurations = true
            }
        }
        
        generatedRoutine = importedRoutine
        scrollToGeneratedToken = UUID()
    }
}

struct WorkoutPlayerView: View {
    let routine: [Exercise]
    let exerciseDuration: Int
    let restDuration: Int
    let restEvery: Int
    let timerStyle: TimerStyle
    let intention: WorkoutIntention
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
    // HR intention banner
    @State private var intentionBannerText: String? = nil
    @State private var intentionBannerTask: Task<Void, Never>? = nil
    @State private var lastBannerExerciseTime: Int = -1
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
        guard let name = currentExercise?.name else { return nil }
        return videoManager.url(for: name)
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
                let height = proxy.size.height
                VStack(spacing: 0) {
                    VStack(spacing: 16) {
                        // Video
                        if VideoMode(rawValue: videoManager.videoMode) != Optional.none {
                            if let player = avPlayer {
                                #if os(macOS)
                                AVPlayerLayerView(player: player)
                                    .frame(height: min(height * 0.35, 220))
                                    .cornerRadius(10)
                                #else
                                VideoPlayer(player: player)
                                    .frame(height: min(height * 0.35, UIDevice.current.userInterfaceIdiom == .pad ? 240 : 180))
                                    .cornerRadius(10)
                                #endif
                            } else if videoURL != nil {
                                Rectangle()
                                    .fill(Color.black.opacity(0.1))
                                #if os(iOS)
                                    .frame(height: min(height * 0.35, UIDevice.current.userInterfaceIdiom == .pad ? 240 : 180))
                                #else
                                    .frame(height: min(height * 0.35, 220))
                                #endif
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
                                #if os(iOS)
                                .frame(height: min(height * 0.35, UIDevice.current.userInterfaceIdiom == .pad ? 240 : 180))
                                #else
                                .frame(height: min(height * 0.35, 220))
                                #endif
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
                                maxHeartRate: userMaxHeartRate
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

                        // Pyramid level indicator
                        if timerStyle == .pyramid && isPlaying {
                            let phase = currentPyramidPhase
                            let interval = WorkoutPlayerView.pyramidIntervals[phase]
                            Text("Pyramid \(phase + 1) of \(WorkoutPlayerView.pyramidIntervals.count)  •  \(isRest ? interval.rest : interval.work)s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Blocks progress indicator
                        if timerStyle == .blocks && isPlaying, let config = blocksConfig {
                            let workBefore = routine[0..<min(currentIndex, routine.count)].filter { $0.name != "Rest" }.count
                            let exercisePos = isRest ? max(0, workBefore - 1) : workBefore
                            let superSetSize = config.blockDurations.count * config.exercisesPerBlock
                            let posInSuperSet = exercisePos % max(1, superSetSize)
                            let blockIdx = min(posInSuperSet / max(1, config.exercisesPerBlock), config.blockDurations.count - 1)
                            let setNum = exercisePos / max(1, superSetSize) + 1
                            Text("Block \(blockIdx + 1) of \(config.blockDurations.count)  •  Set \(setNum)  •  \(config.blockDurations[blockIdx])s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            .overlay(alignment: .top) {
                if let msg = intentionBannerText {
                    IntentionBannerView(message: msg, color: intention.bannerColor)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                        .padding(.horizontal, 16)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: intentionBannerText)
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
    
    private func launchWatchWorkoutSession() {
        #if os(iOS)
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .highIntensityIntervalTraining
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
        let pct = bpm / maxHR
        switch pct {
        case ..<0.60:       return "Zone 1"
        case 0.60..<0.70:   return "Zone 2"
        case 0.70..<0.80:   return "Zone 3"
        case 0.80..<0.90:   return "Zone 4"
        default:             return "Zone 5"
        }
    }

    private func intentionMismatchMessage(hr: Double) -> String? {
        let zone = hrZoneName(bpm: hr, maxHR: userMaxHeartRate)
        switch (intention, zone) {
        case (.fatBurn, "Zone 4"), (.fatBurn, "Zone 5"):
            return "It's okay to ease up — you're burning more carbs than fat right now"
        case (.fatBurn, "Zone 1"):
            return "Try picking up the pace to reach your fat-burn zone"
        case (.cardioEndurance, "Zone 1"):
            return "Push a little harder to build your aerobic base"
        case (.cardioEndurance, "Zone 2") where hr < 110:
            return "A bit more effort will grow your aerobic capacity"
        case (.strengthPower, "Zone 5"):
            return "Great power output — give yourself a solid rest before the next set"
        default:
            return nil
        }
    }

    private func showIntentionBannerIfNeeded(hr: Double) {
        guard let message = intentionMismatchMessage(hr: hr) else { return }
        intentionBannerTask?.cancel()
        withAnimation { intentionBannerText = message }
        intentionBannerTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { intentionBannerText = nil }
        }
    }
}

private struct IntentionBannerView: View {
    let message: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .foregroundStyle(color)
            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}
// MARK: - Array Unique Extension
fileprivate extension Array where Element: Hashable {
    func unique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
// MARK: - WorkoutLiveStatsView

struct WorkoutLiveStatsView: View {
    let exerciseTime: Int
    let heartRate: Double
    let hasWatchData: Bool
    let intention: WorkoutIntention
    let maxHeartRate: Double

    @State private var showingZonePopover = false

    private var hrInfo: (zone: String, color: Color, nutrient: String) {
        let pct = heartRate / maxHeartRate
        switch pct {
        case ..<0.60:       return ("Zone 1", .green, "Active Recovery")
        case 0.60..<0.70:   return ("Zone 2", .yellow, "Fat Burn")
        case 0.70..<0.80:   return ("Zone 3", .orange, "Mixed")
        case 0.80..<0.90:   return ("Zone 4", .red, "Carb Burn")
        default:             return ("Zone 5", .purple, "Peak Effort")
        }
    }

    private var zoneDetails: [String: (bpmRange: String, description: String)] {
        let z1 = Int(maxHeartRate * 0.60)
        let z2 = Int(maxHeartRate * 0.70)
        let z3 = Int(maxHeartRate * 0.80)
        let z4 = Int(maxHeartRate * 0.90)
        return [
            "Zone 1": (bpmRange: "< \(z1) BPM",        description: "Very light. Active recovery."),
            "Zone 2": (bpmRange: "\(z1)–\(z2) BPM",   description: "Light aerobic. Optimal fat oxidation."),
            "Zone 3": (bpmRange: "\(z2)–\(z3) BPM",   description: "Moderate aerobic. Mixed carb/fat fuel."),
            "Zone 4": (bpmRange: "\(z3)–\(z4) BPM",   description: "High intensity. Lactate threshold zone."),
            "Zone 5": (bpmRange: "\(z4)+ BPM",         description: "Maximum effort. Anaerobic capacity."),
        ]
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 2) {
                Image(systemName: "stopwatch")
                    .foregroundStyle(.blue)
                Text(formattedTime(exerciseTime))
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.semibold)
                Text("Ex. Time")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if hasWatchData {
                Divider().frame(height: 40)

                Button {
                    showingZonePopover = true
                } label: {
                    VStack(spacing: 2) {
                        HStack(spacing: 3) {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundStyle(hrInfo.color)
                            Image(systemName: "info.circle")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(hrInfo.zone)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(hrInfo.color)
                        Text("HR Zone")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingZonePopover) {
                    HRZonePopoverView(zone: hrInfo.zone, color: hrInfo.color, intention: intention, maxHeartRate: maxHeartRate)
                }

                Divider().frame(height: 40)
                VStack(spacing: 2) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(hrInfo.color)
                    Text(hrInfo.nutrient)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("Burn Type")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formattedTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct HRZonePopoverView: View {
    let zone: String
    let color: Color
    let intention: WorkoutIntention
    let maxHeartRate: Double

    private var details: [String: (bpmRange: String, description: String)] {
        let z1 = Int(maxHeartRate * 0.60)
        let z2 = Int(maxHeartRate * 0.70)
        let z3 = Int(maxHeartRate * 0.80)
        let z4 = Int(maxHeartRate * 0.90)
        return [
            "Zone 1": (bpmRange: "< \(z1) BPM",        description: "Very light. Active recovery."),
            "Zone 2": (bpmRange: "\(z1)–\(z2) BPM",   description: "Light aerobic. Optimal fat oxidation."),
            "Zone 3": (bpmRange: "\(z2)–\(z3) BPM",   description: "Moderate aerobic. Mixed carb/fat fuel."),
            "Zone 4": (bpmRange: "\(z3)–\(z4) BPM",   description: "High intensity. Lactate threshold zone."),
            "Zone 5": (bpmRange: "\(z4)+ BPM",         description: "Maximum effort. Anaerobic capacity."),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(zone)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                Spacer()
                if let d = details[zone] {
                    Text(d.bpmRange)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let d = details[zone] {
                Text(d.description)
                    .font(.subheadline)
            }
            Divider()
            HStack(spacing: 6) {
                Image(systemName: intention.icon)
                    .foregroundStyle(color)
                Text(intention.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            Text(intention.tip(for: zone))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 240, maxWidth: 300)
    }
}

// MARK: - WorkoutRecapView

struct WorkoutRecapView: View {
    let completedExercises: [String]
    let totalExerciseTime: Int
    let totalRestTime: Int
    let totalCalories: Double
    let peakHeartRate: Double
    let averageHeartRate: Double
    let onDismiss: () -> Void

    private var totalTime: Int { totalExerciseTime + totalRestTime }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.green)
                        Text("Workout Complete!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    .padding(.top, 8)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        RecapStatCard(title: "Total Time",     value: formatted(totalTime),         icon: "clock",            color: .blue)
                        RecapStatCard(title: "Exercise Time",  value: formatted(totalExerciseTime),  icon: "figure.run",       color: .green)
                        RecapStatCard(title: "Exercises Done", value: "\(completedExercises.count)", icon: "checkmark.square", color: .orange)
                        RecapStatCard(title: "Rest Time",      value: formatted(totalRestTime),      icon: "pause.circle",     color: .purple)
                        if totalCalories > 0 {
                            RecapStatCard(title: "Calories",   value: "\(Int(totalCalories)) kcal", icon: "flame.fill",   color: .orange)
                        }
                        if peakHeartRate > 0 {
                            RecapStatCard(title: "Peak HR",    value: "\(Int(peakHeartRate)) BPM",  icon: "heart.fill",   color: .red)
                        }
                        if averageHeartRate > 0 {
                            RecapStatCard(title: "Avg HR",     value: "\(Int(averageHeartRate)) BPM", icon: "heart",      color: .pink)
                        }
                    }

                    if !completedExercises.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Exercises Completed")
                                .font(.headline)
                            ForEach(Array(completedExercises.enumerated()), id: \.offset) { i, name in
                                HStack {
                                    Text("\(i + 1).")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, alignment: .leading)
                                    Text(name)
                                        .font(.subheadline)
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

struct RecapStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - My Exercises

struct MyExercisesView: View {
    @State private var store = CustomExerciseStore.shared
    @State private var showingAdd = false

    let focusAreas: [String]
    let difficulties: [String]

    var body: some View {
        List {
            if store.exercises.isEmpty {
                Text("No custom exercises yet. Tap + to add one.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            ForEach(store.exercises) { exercise in
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.body)
                    Text("\(exercise.focusArea) — \(exercise.difficulty)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                store.remove(at: offsets)
            }
        }
        .navigationTitle("My Exercises")
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
#else
            ToolbarItem {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
#endif
        }
        .sheet(isPresented: $showingAdd) {
            AddExerciseView(focusAreas: focusAreas, difficulties: difficulties) { exercise in
                store.add(exercise)
            }
        }
    }
}

struct AddExerciseView: View {
    let focusAreas: [String]
    let difficulties: [String]
    let onAdd: (UserExercise) -> Void

    @State private var name = ""
    @State private var selectedFocus = ""
    @State private var selectedDifficulty = "Beginner"
    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selectedFocus.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise Name") {
                    TextField("e.g. Diamond Push-Ups", text: $name)
                }
                Section("Focus Area") {
#if os(iOS)
                    Picker("Focus Area", selection: $selectedFocus) {
                        ForEach(focusAreas, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.wheel)
#else
                    Picker("Focus Area", selection: $selectedFocus) {
                        ForEach(focusAreas, id: \.self) { Text($0).tag($0) }
                    }
#endif
                }
                Section("Difficulty") {
                    Picker("Difficulty", selection: $selectedDifficulty) {
                        ForEach(difficulties, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Add Exercise")
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        onAdd(UserExercise(name: name.trimmingCharacters(in: .whitespaces),
                                          focusArea: selectedFocus,
                                          difficulty: selectedDifficulty))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
#else
            .toolbar {
                ToolbarItem { Button("Cancel") { dismiss() } }
                ToolbarItem {
                    Button("Add") {
                        onAdd(UserExercise(name: name.trimmingCharacters(in: .whitespaces),
                                          focusArea: selectedFocus,
                                          difficulty: selectedDifficulty))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
#endif
            .onAppear {
                if selectedFocus.isEmpty { selectedFocus = focusAreas.first ?? "" }
            }
        }
    }
}

// MARK: - TutorialView

struct TutorialView: View {
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
    @State private var page = 0
    @Environment(\.dismiss) private var dismiss

    private struct TutorialPage {
        let title: String
        let body: String
        let icon: String
        let color: Color
    }

    private let pages: [TutorialPage] = [
        TutorialPage(title: "Welcome!", body: "Generate custom bodyweight workouts tailored to your focus areas, difficulty level, and available equipment.", icon: "figure.run", color: .blue),
        TutorialPage(title: "Focus & Equipment", body: "Tap the icon chips to choose which muscle groups to target. Select one or many — the generated workout will draw from those areas. Pick the equipment you have available too.", icon: "figure.mixed.cardio", color: .purple),
        TutorialPage(title: "Saved Routines", body: "Tap 'Saved Routines' on the home screen for expertly curated workouts, including Athlean-X morning stretches, bedtime stretches, and a 10-minute ab routine — each with per-exercise timers built in.", icon: "folder.fill", color: .brown),
        TutorialPage(title: "Audio & Video", body: "Exercise videos stream by default over Wi-Fi/cellular. In Advanced mode you can pre-download them for offline use or disable video entirely. Audio countdown cues play automatically — set your phone to ring (not silent) for sound.", icon: "play.rectangle.fill", color: .pink),
        TutorialPage(title: "Stretch Routine", body: "The Stretch Routine section is completely separate from regular workouts. Set hold duration, choose your categories, and optionally cap the total time — no cardio-style rest intervals.", icon: "figure.cooldown", color: .teal),
        TutorialPage(title: "Set Your Intention", body: "Tell the app your goal — Fat Burn, Cardio Endurance, Strength, or General Fitness. During workouts, tap your HR Zone for personalized zone tips.", icon: "flame", color: .orange),
        TutorialPage(title: "Apple Watch", body: "Pair your Apple Watch to see live heart rate, HR zone, and calorie data. The Watch status bar below the Start button always shows connection state — look for 'Watch Connected' or 'You can also start from your Apple Watch'.", icon: "applewatch", color: .red),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
#if os(macOS)
                pageContent(for: page)
                    .id(page)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if page < pages.count - 1 {
                            withAnimation(.easeInOut(duration: 0.3)) { page += 1 }
                        }
                    }
#else
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, _ in
                        pageContent(for: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
#endif
                HStack(spacing: 16) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { page -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(page == 0)
                    .opacity(page == 0 ? 0.25 : 1)

                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { i in
                            Capsule()
                                .fill(i == page ? Color.primary : Color.secondary.opacity(0.25))
                                .frame(width: 24, height: 4)
                                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { page = i } }
                        }
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { page += 1 }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(page == pages.count - 1)
                    .opacity(page == pages.count - 1 ? 0.25 : 1)
                }
                .padding(.bottom, 20)
            }
            .navigationTitle("Welcome to WorkoutRandomizer")
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip") { hasSeenTutorial = true; dismiss() }
                }
            }
#else
            .toolbar {
                ToolbarItem { Button("Skip") { hasSeenTutorial = true; dismiss() } }
            }
#endif
        }
    }

    @ViewBuilder
    private func pageContent(for index: Int) -> some View {
        let p = pages[index]
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: p.icon)
                .font(.system(size: 72))
                .foregroundStyle(p.color)
            Text(p.title)
                .font(.title)
                .fontWeight(.bold)
            Text(p.body)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            if index == pages.count - 1 {
                Button("Get Started") {
                    hasSeenTutorial = true
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(p.color)
                .controlSize(.large)
            }
            Spacer(minLength: 50)
        }
    }
}

