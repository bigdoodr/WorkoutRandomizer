//  AppVersion.swift
//  Bodyweight WorkoutRandomizer
//
//  The app's own version number, and a comparison that treats it as a version rather than
//  as text.
//
//  This exists because the onboarding guide decides what to show by comparing the running
//  version against the last one the user was walked through, and a plain string comparison
//  gets that wrong in two ways that both bite eventually: "2" and "2.0" are the same release
//  but not the same string, and "2.10" sorts *before* "2.9" alphabetically.

import Foundation

enum AppVersion {
    /// CFBundleShortVersionString — the MARKETING_VERSION set in the Xcode target.
    static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Compares dotted numeric versions component by component, padding the shorter one with
    /// zeros. So "2" == "2.0" == "2.0.0", and "2.10" > "2.9".
    ///
    /// Anything non-numeric in a component reads as 0, which keeps a stray build suffix from
    /// throwing rather than degrading quietly.
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// True when `version` is strictly newer than `other`.
    static func isNewer(_ version: String, than other: String) -> Bool {
        compare(version, other) == .orderedDescending
    }
}
