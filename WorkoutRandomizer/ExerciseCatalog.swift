// ExerciseCatalog.swift
// Manages the exercise catalog with remote fetch from GitHub Pages and bundled fallback.
// When new exercises/videos are added to the site, the app picks them up automatically.

import Foundation
import Observation

// MARK: - Codable Models

struct CatalogExercise: Codable, Equatable {
    let name: String
    let videoPath: String?
    let equipment: [String]?
    let singleSided: Bool?
    let isMovement: Bool?
    let additionalCategories: [String]?
}

struct CatalogData: Codable, Equatable {
    let focusAreas: [String]
    let difficulties: [String]
    let exercises: [String: [String: [CatalogExercise]]]
}

// MARK: - ExerciseCatalog

@MainActor
@Observable
final class ExerciseCatalog {
    static let shared = ExerciseCatalog()

    /// The current exercise catalog data, ready to use.
    private(set) var data: CatalogData

    /// True while a remote fetch is in progress.
    private(set) var isLoading = false

    /// Non-nil if the most recent remote fetch failed (informational only; cached/bundled data is still used).
    private(set) var lastError: Error?

    // Convenience accessors matching the old hardcoded properties
    var focusAreas: [String] { data.focusAreas }
    var difficulties: [String] { data.difficulties }
    var exercises: [String: [String: [Exercise]]] {
        data.exercises.mapValues { difficultyDict in
            difficultyDict.mapValues { catalogExercises in
                catalogExercises.map { Exercise(name: $0.name, videoPath: $0.videoPath, equipment: $0.equipment ?? ["None"], singleSided: $0.singleSided ?? false, isMovement: $0.isMovement ?? false) }
            }
        }
    }

    /// Exercises keyed by secondary category (from additionalCategories), for stretch pool building.
    var exercisesByAdditionalCategory: [String: [Exercise]] {
        var result: [String: [Exercise]] = [:]
        for (_, difficultyDict) in data.exercises {
            for (_, catalogExercises) in difficultyDict {
                for ce in catalogExercises {
                    guard let additional = ce.additionalCategories else { continue }
                    let ex = Exercise(name: ce.name, videoPath: ce.videoPath, equipment: ce.equipment ?? ["None"], singleSided: ce.singleSided ?? false, isMovement: ce.isMovement ?? false)
                    for category in additional {
                        result[category, default: []].append(ex)
                    }
                }
            }
        }
        return result
    }

    /// Exercises keyed by secondary category then difficulty (from additionalCategories),
    /// for pulling cross-tagged bonus exercises (e.g. "Cardio") into a difficulty-filtered pool.
    var exercisesByAdditionalCategoryAndDifficulty: [String: [String: [Exercise]]] {
        var result: [String: [String: [Exercise]]] = [:]
        for (_, difficultyDict) in data.exercises {
            for (level, catalogExercises) in difficultyDict {
                for ce in catalogExercises {
                    guard let additional = ce.additionalCategories else { continue }
                    let ex = Exercise(name: ce.name, videoPath: ce.videoPath, equipment: ce.equipment ?? ["None"], singleSided: ce.singleSided ?? false, isMovement: ce.isMovement ?? false)
                    for category in additional {
                        result[category, default: [:]][level, default: []].append(ex)
                    }
                }
            }
        }
        return result
    }

    /// Flat dictionary of exercise name -> video path, for VideoManager.
    var videoPaths: [String: String] {
        var result: [String: String] = [:]
        for (_, difficultyDict) in data.exercises {
            for (_, exerciseList) in difficultyDict {
                for exercise in exerciseList {
                    if let path = exercise.videoPath {
                        result[exercise.name] = path
                    }
                }
            }
        }
        return result
    }

    private static let remoteURL = URL(string: "https://bigdoodr.github.io/exercises.json")!
    private static let cacheFileName = "exercises_cache.json"

    private init() {
        // Load the best available data synchronously so the UI is never empty:
        // 1. Try disk cache (may be newer than bundle)
        // 2. Fall back to bundled exercises.json
        if let cached = Self.loadFromDiskCache() {
            data = Self.backfillMetadata(cached)
        } else {
            data = Self.loadBundled()
        }
    }

    /// Fetch the latest catalog from the remote server. Call this on app launch.
    func refresh() async {
        isLoading = true
        lastError = nil

        do {
            let (jsonData, _) = try await URLSession.shared.data(from: Self.remoteURL)
            let decoded = Self.backfillMetadata(try JSONDecoder().decode(CatalogData.self, from: jsonData))
            // Only update if the data actually changed
            if decoded != data {
                data = decoded
            }
            // Cache to disk for next cold launch
            Self.saveToDiskCache(jsonData)
            lastError = nil
        } catch {
            // Remote fetch failed — the app continues with cached/bundled data
            lastError = error
            print("ExerciseCatalog: remote fetch failed — using cached data. Error: \(error.localizedDescription)")
        }

        isLoading = false
    }

    // MARK: - Metadata Backfill

    /// The remote catalog may lag behind the app bundle and omit newer per-exercise
    /// metadata. Fill in any missing values from the bundled catalog, matched by
    /// exercise name, so features like "Both Sides" and "Move/Hold" keep working
    /// regardless of which catalog source is active.
    private static func backfillMetadata(_ incoming: CatalogData) -> CatalogData {
        let bundled = loadBundled()

        var bundledSingleSided: [String: Bool] = [:]
        var bundledIsMovement: [String: Bool] = [:]
        var bundledAdditionalCategories: [String: [String]] = [:]
        for (_, difficultyDict) in bundled.exercises {
            for (_, exerciseList) in difficultyDict {
                for exercise in exerciseList {
                    if let flag = exercise.singleSided { bundledSingleSided[exercise.name] = flag }
                    if let flag = exercise.isMovement { bundledIsMovement[exercise.name] = flag }
                    if let cats = exercise.additionalCategories { bundledAdditionalCategories[exercise.name] = cats }
                }
            }
        }

        let mergedExercises = incoming.exercises.mapValues { difficultyDict in
            difficultyDict.mapValues { exerciseList in
                exerciseList.map { exercise in
                    CatalogExercise(
                        name: exercise.name,
                        videoPath: exercise.videoPath,
                        equipment: exercise.equipment,
                        singleSided: exercise.singleSided ?? bundledSingleSided[exercise.name],
                        isMovement: exercise.isMovement ?? bundledIsMovement[exercise.name],
                        additionalCategories: exercise.additionalCategories ?? bundledAdditionalCategories[exercise.name]
                    )
                }
            }
        }
        return CatalogData(
            focusAreas: incoming.focusAreas,
            difficulties: incoming.difficulties,
            exercises: mergedExercises
        )
    }

    // MARK: - Bundled Fallback

    private static func loadBundled() -> CatalogData {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
              let jsonData = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CatalogData.self, from: jsonData) else {
            fatalError("Missing or invalid bundled exercises.json — the app cannot function without exercise data.")
        }
        return decoded
    }

    // MARK: - Disk Cache

    private static var cacheFileURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent(cacheFileName)
    }

    private static func loadFromDiskCache() -> CatalogData? {
        let url = cacheFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let jsonData = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CatalogData.self, from: jsonData) else {
            return nil
        }
        return decoded
    }

    private static func saveToDiskCache(_ jsonData: Data) {
        do {
            try jsonData.write(to: cacheFileURL, options: .atomic)
        } catch {
            print("ExerciseCatalog: failed to write cache — \(error.localizedDescription)")
        }
    }
}
