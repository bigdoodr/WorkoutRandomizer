//  RoomyPlayerParts.swift
//  Bodyweight WorkoutRandomizer
//
//  Pieces the three players add when there's room beneath the video (regular-width layouts — the
//  Duo's inner display, iPads): larger name / Up Next / "N of M" text that scales with the
//  available height, an "Up Next" card with a still from the next exercise's demo video, and a
//  thin whole-workout progress bar with a segment per exercise.
//
//  The video itself is never cropped or enlarged by any of this; these only use the space below it.

#if os(iOS)
import SwiftUI
import AVFoundation
import UIKit

// MARK: - Scaling

enum RoomyMetrics {
    /// How much to scale the text beneath the video for the height available: 1× up to a
    /// phone-sized layout, growing to 2× on a tall one.
    static func scale(forHeight height: CGFloat) -> CGFloat {
        min(max(height / 700, 1), 2)
    }
}

// MARK: - Still thumbnails

/// Pulls a single still frame out of a demo video, caching the result. Works for local files and
/// streamed URLs alike; if the frame can't be read it simply returns nil.
@MainActor
final class VideoThumbnails {
    static let shared = VideoThumbnails()

    private let cache = NSCache<NSURL, UIImage>()
    private var inflight: [URL: Task<UIImage?, Never>] = [:]

    func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if let running = inflight[url] { return await running.value }

        let task = Task<UIImage?, Never> {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 360)
            // Any nearby frame will do; don't make it decode to an exact time.
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity
            guard let result = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)) else { return nil }
            return UIImage(cgImage: result.image)
        }
        inflight[url] = task
        let image = await task.value
        inflight[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}

/// A 16:9 still from `url`. Shows a placeholder until (or unless) the frame is available.
struct VideoThumbnail: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.gray.opacity(0.15))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "video")
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: url) {
            guard let url else { image = nil; return }
            image = await VideoThumbnails.shared.image(for: url)
        }
    }
}

// MARK: - Up Next card

/// "Up Next": the next exercise's name beside a still from its demo video (omitted when it has no
/// video). Shown on rest screens too, where it's the exercise coming after the rest.
struct UpNextCard: View {
    let name: String
    /// e.g. "after a 10s rest" when a rest comes first.
    var note: String? = nil
    /// The next exercise's demo video, if it has one.
    var videoURL: URL? = nil
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 12 * scale) {
            if videoURL != nil {
                VideoThumbnail(url: videoURL)
                    .frame(width: 150 * scale)
            }
            VStack(alignment: .leading, spacing: 4 * scale) {
                Text("UP NEXT")
                    .font(.system(size: 12 * scale, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.system(size: 22 * scale, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let note {
                    Text(note)
                        .font(.system(size: 14 * scale))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Up next: \(name)\(note.map { ", \($0)" } ?? "")")
    }
}

// MARK: - Whole-workout progress

/// A thin bar with one segment per exercise: done, current, and still to come.
struct WorkoutSegmentBar: View {
    let total: Int
    /// Zero-based index of the current exercise.
    let current: Int
    var tint: Color = .accentColor

    var body: some View {
        if total > 0 {
            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(index < current ? tint : (index == current ? tint.opacity(0.55) : Color.gray.opacity(0.25)))
                        .frame(height: 5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Exercise \(min(current + 1, total)) of \(total)")
        }
    }
}
#endif
