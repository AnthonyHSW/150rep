//
//  ContentView.swift
//  rep150
//
//  Created by Oliver Larsson on 10/16/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            LiveView()
                .tabItem {
                    Label("Live", systemImage: "waveform.path.ecg")
                }

            WorkoutsView()
                .tabItem {
                    Label("Workouts", systemImage: "dumbbell")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
        .background(AppColors.pageBackground)
        .task {
            // Runs behind the auth gate, so there is a signed-in user by now. Everything
            // finished while offline is outstanding at this point, as is every workout
            // recorded before syncing existed — so this is the backfill too, with no
            // one-time path to maintain.
            do {
                try await WorkoutSyncService.syncPending(
                    store: WorkoutStore(modelContext: modelContext)
                )
            } catch {
                print("Workout sync deferred: \(error)")
            }
        }
    }
}

#Preview {
    ContentView()
}
