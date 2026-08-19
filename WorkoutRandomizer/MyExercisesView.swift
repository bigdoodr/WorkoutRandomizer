//  MyExercisesView.swift
//  Bodyweight WorkoutRandomizer
//
//  User-defined custom exercise list and the add-exercise form.
//  Extracted from WorkoutRandomizer.swift — no behaviour change.

import SwiftUI
internal import UniformTypeIdentifiers
import Observation
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
#endif

// MARK: - My Exercises

struct MyExercisesView: View {
    @State private var store = CustomExerciseStore.shared
    @State private var showingAdd = false

    let focusAreas: [String]
    let difficulties: [String]

    var body: some View {
        List {
            if store.exercises.isEmpty {
                Text("No custom exercises yet. Tap + to add one.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            ForEach(store.exercises) { exercise in
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.body)
                    Text("\(exercise.focusArea) — \(exercise.difficulty)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                store.remove(at: offsets)
            }
        }
        .navigationTitle("My Exercises")
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
#else
            ToolbarItem {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
#endif
        }
        .sheet(isPresented: $showingAdd) {
            AddExerciseView(focusAreas: focusAreas, difficulties: difficulties) { exercise in
                store.add(exercise)
            }
        }
    }
}

struct AddExerciseView: View {
    let focusAreas: [String]
    let difficulties: [String]
    let onAdd: (UserExercise) -> Void

    @State private var name = ""
    @State private var selectedFocus = ""
    @State private var selectedDifficulty = "Beginner"
    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selectedFocus.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise Name") {
                    TextField("e.g. Diamond Push-Ups", text: $name)
                }
                Section("Focus Area") {
#if os(iOS)
                    Picker("Focus Area", selection: $selectedFocus) {
                        ForEach(focusAreas, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.wheel)
#else
                    Picker("Focus Area", selection: $selectedFocus) {
                        ForEach(focusAreas, id: \.self) { Text($0).tag($0) }
                    }
#endif
                }
                Section("Difficulty") {
                    Picker("Difficulty", selection: $selectedDifficulty) {
                        ForEach(difficulties, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Add Exercise")
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        onAdd(UserExercise(name: name.trimmingCharacters(in: .whitespaces),
                                          focusArea: selectedFocus,
                                          difficulty: selectedDifficulty))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
#else
            .toolbar {
                ToolbarItem { Button("Cancel") { dismiss() } }
                ToolbarItem {
                    Button("Add") {
                        onAdd(UserExercise(name: name.trimmingCharacters(in: .whitespaces),
                                          focusArea: selectedFocus,
                                          difficulty: selectedDifficulty))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
#endif
            .onAppear {
                if selectedFocus.isEmpty { selectedFocus = focusAreas.first ?? "" }
            }
        }
    }
}
