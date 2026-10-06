//  HRZonesSettingsView.swift
//  Bodyweight WorkoutRandomizer
//
//  Shows where the app's heart-rate zones come from — Health's reported age, or the default
//  assumption when that's unavailable — and lets the user override either the age or the zone
//  boundaries directly, the way Gentle Health does.

import SwiftUI

struct HRZonesSettingsView: View {
    @State private var hrZones = HRZoneSettings.shared

    private static let zoneNames = ["Zone 1", "Zone 2", "Zone 3", "Zone 4", "Zone 5"]
    private static let zoneLabels = ["Active Recovery", "Fat Burn", "Mixed", "Carb Burn", "Peak Effort"]
    private static let zoneColors: [Color] = [.green, .yellow, .orange, .red, .purple]

    private var manualAgeBinding: Binding<Bool> {
        Binding(
            get: { hrZones.manualAgeOverride != nil },
            set: { enabled in
                hrZones.manualAgeOverride = enabled ? hrZones.effectiveAge : nil
            }
        )
    }

    private var ageBinding: Binding<Int> {
        Binding(
            get: { hrZones.manualAgeOverride ?? hrZones.effectiveAge },
            set: { hrZones.manualAgeOverride = $0 }
        )
    }

    private func boundaryBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: {
                let boundaries = hrZones.customBoundaries
                return index < boundaries.count ? Int(boundaries[index]) : Int(hrZones.zoneBoundaries[index])
            },
            set: { newValue in
                var boundaries = hrZones.customBoundaries
                if boundaries.count == 4 {
                    boundaries[index] = Double(newValue)
                    hrZones.customBoundaries = boundaries
                }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                statusText
            } header: {
                Text("Your Age")
            }

            Section {
                zoneRow(label: "Zone 0", nutrient: "Resting", color: .blue, range: restingRangeText)
                ForEach(0..<5, id: \.self) { index in
                    zoneRow(
                        label: Self.zoneNames[index],
                        nutrient: Self.zoneLabels[index],
                        color: Self.zoneColors[index],
                        range: zoneRangeText(index)
                    )
                }
            } header: {
                Text("Heart Rate Zones")
            } footer: {
                zonesFooterText
            }

            Section {
                Toggle("Set Age Manually", isOn: manualAgeBinding)
                if hrZones.manualAgeOverride != nil {
                    Stepper(value: ageBinding, in: 10...100) {
                        HStack {
                            Text("Age")
                            Spacer()
                            Text("\(ageBinding.wrappedValue)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Age Override")
            } footer: {
                Text("Overrides whatever Health reports, or the default assumption of \(HRZoneSettings.defaultAssumedAge) if Health access isn't available.")
            }

            Section {
                Toggle("Customize Zone Boundaries", isOn: $hrZones.useCustomBoundaries)
                if hrZones.useCustomBoundaries {
                    ForEach(0..<4, id: \.self) { index in
                        Stepper(value: boundaryBinding(index), in: 40...220) {
                            HStack {
                                Text("Zone \(index + 1) | \(index + 2) Cutoff")
                                Spacer()
                                Text("\(boundaryBinding(index).wrappedValue) bpm")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Reset to Calculated") {
                        hrZones.resetCustomBoundaries()
                    }
                }
            } header: {
                Text("Zone Boundaries")
            } footer: {
                Text("Set the bpm where each zone ends and the next begins, instead of using the calculated percentages of your max heart rate. Note: if your Apple Watch already has its own Heart Rate Zones set up, the Watch uses those during a workout instead of this override.")
            }
        }
        .navigationTitle("Heart Rate Zones")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task {
            await hrZones.refreshFromHealthKit()
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch hrZones.healthAgeStatus {
        case .authorized(let age):
            if hrZones.manualAgeOverride != nil {
                Text("You allowed this app to access your age from the Health app. It indicates you're \(age) years old, but you've manually set your age below — the zones use your manual value instead.")
                    .foregroundStyle(.secondary)
            } else {
                Text("You allowed this app to access your age from the Health app. It indicates you're \(age) years old. Here's how that breaks down per zone:")
            }
        case .notRequested, .unavailable:
            if hrZones.manualAgeOverride != nil {
                Text("Health access to your age isn't available, but you've manually set your age below — the zones use your manual value instead.")
                    .foregroundStyle(.secondary)
            } else {
                Text("We don't have access to your age from the Health app — it may have been denied, or no birth date is set in Health. The zones below use a default assumption of age \(HRZoneSettings.defaultAssumedAge).")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var zonesFooterText: some View {
        switch hrZones.boundarySource {
        case .watch:
            Text("These boundaries were last synced from your Apple Watch's own Heart Rate Zones — since your Watch already has zones configured, it uses those during a workout instead of the calculated estimate (or any custom boundaries set below).")
        case .custom:
            Text("Zones 1 through 5 use the custom boundaries you set below.")
        case .calculated:
            Text("Zones 1 through 5 are estimated from your max heart rate (220 minus age) and are what the app uses to classify your heart rate during a workout when your Apple Watch hasn't already supplied its own zones.")
        }
    }

    private var restingRangeText: String {
        if let resting = hrZones.restingHeartRate {
            return "~\(Int(resting)) bpm (from Health)"
        }
        return "Not available from Health"
    }

    private func zoneRangeText(_ index: Int) -> String {
        let boundaries = hrZones.displayBoundaries
        let lower = index > 0 ? Int(boundaries[index - 1]) : nil
        let upper = index < boundaries.count ? Int(boundaries[index]) : nil
        switch (lower, upper) {
        case (nil, let u?): return "< \(u) bpm"
        case (let l?, nil): return "\(l)+ bpm"
        case (let l?, let u?): return "\(l)–\(u) bpm"
        default: return "—"
        }
    }

    @ViewBuilder
    private func zoneRow(label: String, nutrient: String, color: Color, range: String) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .fontWeight(.medium)
                Text(nutrient)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(range)
                .foregroundStyle(.secondary)
        }
    }
}
