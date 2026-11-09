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
    /// Where the user stands with the Health sheet for the app's full type list.
    enum HealthRequestState: Equatable {
        /// Not checked yet, or Health couldn't say (it can take a moment right after a fresh
        /// install). Show neither "Connect" nor "connected".
        case unknown
        /// The system would still show the sheet — the user hasn't answered.
        case pending
        /// Answered, whichever way. Changing it later happens in the Health app.
        case answered
    }
    private(set) var healthRequestState: HealthRequestState = .unknown
    /// True while the Health sheet is still waiting on the user. Drives the "Connect Apple
    /// Health" rows.
    var healthRequestPending: Bool { healthRequestState == .pending }

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

    /// The four boundaries last reported by Apple Watch's own HKWorkoutZoneConfiguration, synced
    /// over from a workout session. When present, this is what the Watch actually enforces live —
    /// it ignores this app's calculated or custom boundaries entirely — so it takes priority for
    /// display purposes even though it isn't used by `zoneBoundaries`' fallback math below.
    private(set) var watchZoneThresholds: [Double]? {
        didSet {
            if let watchZoneThresholds {
                defaults.set(watchZoneThresholds, forKey: Keys.watchZoneThresholds)
            } else {
                defaults.removeObject(forKey: Keys.watchZoneThresholds)
            }
        }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let manualAge = "hrZone_manualAgeOverride"
        static let useCustomBoundaries = "hrZone_useCustomBoundaries"
        static let customBoundaries = "hrZone_customBoundaries"
        static let watchZoneThresholds = "hrZone_watchThresholds"
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
        if let stored = defaults.array(forKey: Keys.watchZoneThresholds) as? [Double], stored.count == 4 {
            watchZoneThresholds = stored
        } else {
            watchZoneThresholds = nil
        }
        // self is fully initialized now, so calculatedBoundaries (which reads effectiveAge) is
        // safe to call — give the editor sensible starting values when nothing is stored yet.
        if customBoundaries.count != 4 {
            customBoundaries = calculatedBoundaries
        }
    }

    /// Records the boundaries Apple Watch just reported for a workout, so the Settings screen can
    /// keep showing them even after the session ends.
    func updateWatchZoneThresholds(_ thresholds: [Double]) {
        guard thresholds.count == 4 else { return }
        watchZoneThresholds = thresholds.sorted()
    }

    enum BoundarySource: Equatable {
        case watch
        case custom
        case calculated
    }

    /// Where `displayBoundaries` below is actually coming from — drives the explanatory copy in
    /// Settings.
    var boundarySource: BoundarySource {
        if watchZoneThresholds != nil { return .watch }
        return useCustomBoundaries ? .custom : .calculated
    }

    /// The boundaries to show the user: Apple Watch's real, already-active zones when we know
    /// them, else whatever `zoneBoundaries` would compute.
    var displayBoundaries: [Double] {
        watchZoneThresholds ?? zoneBoundaries
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
    /// Set while the Health sheet is up, so overlapping callers share one request.
    private var healthRequestTask: Task<Void, Never>?

    /// Asks for the app's whole Health list (`HealthAccess`) in one request, then reloads. This is
    /// the only place the iPhone shows the Health sheet.
    func requestHealthAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        if let healthRequestTask {
            await healthRequestTask.value
            return
        }
        let task = Task { @MainActor in
            _ = try? await HealthAccess.request(from: HKHealthStore())
        }
        healthRequestTask = task
        await task.value
        healthRequestTask = nil
        await refreshFromHealthKit()
    }

    /// Shows the Health sheet only if the user hasn't answered it yet. Call before anything that
    /// can wake the Watch, so the iPhone is always where the question is asked first.
    func requestHealthAccessIfNeeded() async {
        await refreshHealthRequestStatus()
        // Also covers "unknown": requesting when the user has already answered shows nothing.
        if healthRequestState != .answered { await requestHealthAccess() }
    }

    /// Re-reads whether the Health sheet is still pending. Never prompts. Health can answer
    /// "unknown" for a moment right after install, so retry briefly before giving up.
    func refreshHealthRequestStatus() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthRequestState = .answered
            return
        }
        let store = HKHealthStore()
        for attempt in 0..<5 {
            switch await HealthAccess.requestStatus(for: store) {
            case .shouldRequest:
                healthRequestState = .pending
                return
            case .unnecessary:
                healthRequestState = .answered
                return
            default:
                healthRequestState = .unknown
                if attempt < 4 { try? await Task.sleep(for: .seconds(1)) }
            }
        }
    }

    /// Reads date of birth and resting heart rate and updates `healthAgeStatus` /
    /// `restingHeartRate`. Read-only: it never shows the Health sheet (see `requestHealthAccess`),
    /// so it's safe to call whenever a screen appears.
    func refreshFromHealthKit() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthAgeStatus = .unavailable
            healthRequestState = .answered
            return
        }
        await refreshHealthRequestStatus()
        // Nothing to read until the user has answered; leave the age as "not requested".
        guard healthRequestState == .answered else {
            healthAgeStatus = .notRequested
            return
        }
        let store = HKHealthStore()

        do {
            let components = try store.dateOfBirthComponents()
            if let year = components.year {
                // Subtracting years alone counts anyone who hasn't had this year's birthday yet
                // as a year older than they are. Use the full birth date when Health provides
                // month/day so the age only ticks over on the actual birthday.
                let age: Int
                if let month = components.month, let day = components.day,
                   let birthDate = Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) {
                    age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
                        ?? (Calendar.current.component(.year, from: Date()) - year)
                } else {
                    age = Calendar.current.component(.year, from: Date()) - year
                }
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
        let type = HKQuantityType(.restingHeartRate)
        let sort = SortDescriptor(\HKQuantitySample.endDate, order: .reverse)
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type)], sortDescriptors: [sort], limit: 1)
        guard let sample = try? await descriptor.result(for: store).first else { return }
        restingHeartRate = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }
#endif
}
