//
//  ContentView.swift
//  rep150
//
//  Created by Oliver Larsson on 10/16/26.
//

import SwiftUI

struct ContentView: View {
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

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
        .background(AppColors.pageBackground)
    }
}

#Preview {
    ContentView()
}
