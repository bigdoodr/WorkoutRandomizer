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
