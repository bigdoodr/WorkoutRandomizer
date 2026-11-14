//  StretchPlan.swift
//  Bodyweight WorkoutRandomizer
//
//  Turns a stretch session into the slots the plan clock runs: an optional lead-in "Get Ready",
//  then for each stretch (after the first) a "Get Ready" slot, then its hold — twice, Left Side
//  then Right Side, for a single-sided stretch in Both Sides mode. The hold length is already
//  applied, so the Watch needs no stretch logic.
//
//  Alongside the plan comes a role for each slot, so the iPhone player can map the clock's slot
//  back onto its own state (which stretch, which side, whether it's a "Get Ready").

import Foundation

struct StretchPlanItem: Equatable {
    let name: String
    let singleSided: Bool
}

/// What a plan slot means to the stretch player.
struct StretchSlotRole: Equatable {
    let stretchIndex: Int
    /// 0 = first (left) side, 1 = second (right) side.
    let side: Int
    /// A "Get Ready" slot rather than a hold.
    let isTransition: Bool
}

enum StretchPlanBuilder {
    static let transitionName = "Get Ready"

    static func build(
        items: [StretchPlanItem],
        holdDuration: Int,
        bothSides: Bool,
        transitionDuration: Int,
        leadIn: Bool,
        activityTypeRaw: UInt?,
        planID: String = UUID().uuidString,
        createdAt: TimeInterval = Date().timeIntervalSince1970
    ) -> (plan: WorkoutPlan, roles: [StretchSlotRole]) {
        var slots: [PlanSlot] = []
        var roles: [StretchSlotRole] = []

        for (index, item) in items.enumerated() {
            let followingName: String? = index + 1 < items.count ? items[index + 1].name : nil

            // "Get Ready": before the first stretch only when the session was started with a
            // lead-in (from the Watch), and before every later stretch.
            if index > 0 || leadIn {
                slots.append(PlanSlot(name: transitionName, isRest: true, duration: transitionDuration,
                                      groupIndex: index, nextName: item.name, hasNextName: true))
                roles.append(StretchSlotRole(stretchIndex: index, side: 0, isTransition: true))
            }

            let twoSides = bothSides && item.singleSided
            slots.append(PlanSlot(name: item.name, isRest: false, duration: holdDuration,
                                  sideLabel: twoSides ? "Left Side" : nil,
                                  groupIndex: index, nextName: followingName, hasNextName: true))
            roles.append(StretchSlotRole(stretchIndex: index, side: 0, isTransition: false))

            if twoSides {
                slots.append(PlanSlot(name: item.name, isRest: false, duration: holdDuration,
                                      sideLabel: "Right Side",
                                      groupIndex: index, nextName: followingName, hasNextName: true))
                roles.append(StretchSlotRole(stretchIndex: index, side: 1, isTransition: false))
            }
        }

        let plan = WorkoutPlan(id: planID, createdAt: createdAt, slots: slots,
                               activityTypeRaw: activityTypeRaw, groupCount: items.count)
        return (plan, roles)
    }
}
