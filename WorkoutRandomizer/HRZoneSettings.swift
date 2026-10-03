//  HRZoneSettings.swift
//  Bodyweight WorkoutRandomizer
//
//  Single source of truth for heart-rate-zone data: the age HealthKit reports (or doesn't),
//  the resulting max-HR estimate, and any manual overrides the user sets in Settings.
//
//  This only backs the *fallback* zone math — the percentage-of-max-HR classification used
//  by WorkoutPlayerView and WorkoutLiveStatsView whenever a live Apple Watch session hasn't
//  already supplied its own HealthKit zone thresholds. It deliberately does not reach into the
//  watch's native HKWorkoutZoneConfiguration pipeline or the recap screen's zone tracking —
//  those take the watch's thresholds as the authority whenever they're available.

import Foundation
import Observation
#if canImport(HealthKit)
import HealthKit
#endif

@MainActor
@Observable
final class HRZoneSettings {
    static let shared = HRZoneSettings()

    static let defaultAssumedAge = 35
    /// Fraction of max HR at each Zone 1|2, 2|3, 3|4, 4|5 boundary — the same cutoffs that used
    /// to be hardcoded independently in WorkoutPlayerView and WorkoutLiveStatsView.
    static let defaultBoundaryFractions: [Double] = [0.60, 0.70, 0.80, 0.90]

    enum HealthAgeStatus: Equatable {
        case notRequested
        case authorized(age: Int)
        /// Denied, restricted, or Health simply has no birthdate on file — HealthKit can't tell
        /// an app which of those it is, so this covers all three.
        case unavailable
    }

    private(set) var healthAgeStatus: HealthAgeStatus = .notRequested
    private(set) var restingHeartRate: Double?

    // Real stored properties, not computed pass-throughs to UserDefaults: @Observable only
    // instruments actual stored properties, so a pure get/set-over-UserDefaults property would
    // never tell SwiftUI a view needs to re-render when it changes.
    var manualAgeOverride: Int? {
        didSet {
            if let manualAgeOverride {
                defaults.set(manualAgeOverride, forKey: Keys.manualAge)
            } else {
                defaults.removeObject(forKey: Keys.manualAge)
            }
        }
    }

    var useCustomBoundaries: Bool {
        didSet { defaults.set(useCustomBoundaries, forKey: Keys.useCustomBoundaries) }
    }

    /// Four ascending bpm cut points between Zones 1-5. Only meaningful when
    /// `useCustomBoundaries` is on.
    var customBoundaries: [Double] {
        didSet { defaults.set(customBoundaries, forKey: Keys.customBoundaries) }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let manualAge = "hrZone_manualAgeOverride"
        static let useCustomBoundaries = "hrZone_useCustomBoundaries"
        static let customBoundaries = "hrZone_customBoundaries"
    }

    private init() {
        let storedAge = defaults.integer(forKey: Keys.manualAge)
        manualAgeOverride = storedAge > 0 ? storedAge : nil
        useCustomBoundaries = defaults.bool(forKey: Keys.useCustomBoundaries)
        if let stored = defaults.array(forKey: Keys.customBoundaries) as? [Double], stored.count == 4 {
            customBoundaries = stored
        } else {
            customBoundaries = []
        }
        // self is fully initialized now, so calculatedBoundaries (which reads effectiveAge) is
        // safe to call — give the editor sensible starting values when nothing is stored yet.
        if customBoundaries.count != 4 {
            customBoundaries = calculatedBoundaries
        }
    }

    /// The age actually driving the max-HR formula: a manual override first, then what Health
    /// reported, then a reasonable assumption — in that order.
    var effectiveAge: Int {
        if let manualAgeOverride { return manualAgeOverride }
        if case .authorized(let age) = healthAgeStatus { return age }
        return Self.defaultAssumedAge
    }

    /// Whether the zones below are a personal estimate or just the generic default — drives the
    /// warning badge over the Settings tab icon.
    var isAgeMissing: Bool {
        if manualAgeOverride != nil { return false }
        if case .authorized = healthAgeStatus { return false }
        return true
    }

    var maxHeartRate: Double { 220.0 - Double(effectiveAge) }

    private var calculatedBoundaries: [Double] {
        Self.defaultBoundaryFractions.map { maxHeartRate * $0 }
    }

    /// Ascending bpm cut points between Zones 1-5 — the manual override when set, else derived
    /// from `maxHeartRate`. Sorted so an editor that lets each boundary move independently can
    /// never produce an out-of-order zone classification.
    var zoneBoundaries: [Double] {
        useCustomBoundaries ? customBoundaries.sorted() : calculatedBoundaries
    }

    func resetCustomBoundaries() {
        useCustomBoundaries = false
        customBoundaries = calculatedBoundaries
    }

    /// Classifies a live heart rate into "Zone 1" through "Zone 5" using `zoneBoundaries`.
    func zoneName(forHeartRate bpm: Double) -> String {
        let idx = zoneBoundaries.firstIndex(where: { bpm < $0 }) ?? zoneBoundaries.count
        return "Zone \(idx + 1)"
    }

#if canImport(HealthKit)
    /// Requests read access to date of birth (and, opportunistically, resting heart rate) and
    /// updates `healthAgeStatus`/`restingHeartRate`. Safe to call repeatedly — HealthKit only
    /// prompts the user the first time a given type is requested.
    func refreshFromHealthKit() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthAgeStatus = .unavailable
            return
        }
        let store = HKHealthStore()
        guard let dobType = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) else {
            healthAgeStatus = .unavailable
            return
        }

        do {
            try await store.requestAuthorization(toShare: [], read: [dobType])
            let components = try store.dateOfBirthComponents()
            if let year = components.year {
                let age = Calendar.current.component(.year, from: Date()) - year
                if age > 10, age < 120 {
                    healthAgeStatus = .authorized(age: age)
                } else {
                    healthAgeStatus = .unavailable
                }
            } else {
                healthAgeStatus = .unavailable
            }
        } catch {
            healthAgeStatus = .unavailable
        }

        await refreshRestingHeartRate(store: store)
    }

    private func refreshRestingHeartRate(store: HKHealthStore) async {
        guard let type = HKObjectType.quantityType(forIdentifier: .restingHeartRate) else { return }
        guard (try? await store.requestAuthorization(toShare: [], read: [type])) != nil else { return }

        let sort = SortDescriptor(\HKQuantitySample.endDate, order: .reverse)
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type)], sortDescriptors: [sort], limit: 1)
        guard let sample = try? await descriptor.result(for: store).first else { return }
        restingHeartRate = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }
#endif
}
