//  ExerciseNumbering.swift
//  Bodyweight WorkoutRandomizer
//
//  The "Exercise N of M" count: exercises only. Rests don't count, and neither does a
//  single-sided exercise's second side — both of an exercise's sides are one exercise, the way a
//  stretch's two sides are one stretch.
//
//  Each slot of a routine is described by the exercise that owns it (`nil` for a rest). A rest
//  takes the number of the exercise that follows it — so on a rest screen the count points at
//  what's coming — or the last exercise's number if nothing follows.

import Foundation

enum ExerciseNumbering {

    /// For every slot, the 1-based number of its exercise, and the number of exercises in all.
    /// `owners[i]` identifies the exercise slot `i` belongs to, or is nil for a rest.
    static func ordinals(for owners: [Int?]) -> (ordinals: [Int], total: Int) {
        var order: [Int: Int] = [:]               // exercise id -> 1-based position
        for owner in owners {
            if let owner, order[owner] == nil { order[owner] = order.count + 1 }
        }
        let total = order.count
        var result: [Int] = []
        result.reserveCapacity(owners.count)
        for (index, owner) in owners.enumerated() {
            if let owner {
                result.append(order[owner] ?? 0)
            } else if let next = owners[(index + 1)...].compactMap({ $0 }).first {
                result.append(order[next] ?? total)
            } else {
                result.append(total)
            }
        }
        return (result, total)
    }
}
