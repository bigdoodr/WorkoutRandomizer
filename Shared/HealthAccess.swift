// HealthAccess.swift
// The one list of Health types the app asks about, shared by the iPhone and Watch targets.
//
// Both targets must request exactly this set. HealthKit decides whether a request still needs
// to be shown by comparing the types asked for against what the user has already answered, so
// two slightly different lists would make the second device prompt again.

#if canImport(HealthKit)
import HealthKit

nonisolated enum HealthAccess {
    /// What the app writes: the finished workout.
    static var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType()]
    }

    /// What the app reads: live heart rate and calories, resting heart rate (for zones), date of
    /// birth (for age-based zones) and workouts.
    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.restingHeartRate),
        ]
        if let dateOfBirth = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            types.insert(dateOfBirth)
        }
        return types
    }

    /// Whether the system would still show the Health sheet for this set. Never prompts.
    static func requestStatus(for store: HKHealthStore) async -> HKAuthorizationRequestStatus {
        (try? await store.statusForAuthorizationRequest(toShare: shareTypes, read: readTypes)) ?? .unknown
    }

    /// Shows the Health sheet for the full set in one request.
    static func request(from store: HKHealthStore) async throws {
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }
}
#endif
