//
//  rep150App.swift
//  rep150
//
//  Created by Oliver Larsson on 10/16/26.
//

import SwiftUI
import SwiftData

@main
struct rep150App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    try? await AuthService.ensureSession()
                }
        }
        .modelContainer(
            for: [WorkoutSession.self, ExerciseLog.self, ExerciseSet.self, WorkoutPhoto.self]
        )
    }
}
