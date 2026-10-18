//
//  rep150App.swift
//  rep150
//
//  Created by Oliver Larsson on 10/16/26.
//

import SwiftUI
import SwiftData
import Supabase

@main
struct rep150App: App {
    @State private var auth = AuthService.shared

    /// Applied at the root so the override covers the login wall and every sheet and
    /// full-screen cover too — those are presented outside the tab view's hierarchy, so a
    /// modifier further down would leave them on the system appearance.
    @AppStorage(PreferenceKey.appearance) private var appearance = AppearanceSetting.system

    var body: some Scene {
        WindowGroup {
            AuthGate(auth: auth)
                .task { auth.start() }
                .onOpenURL { url in
                    // The Google flow normally returns through
                    // ASWebAuthenticationSession, which resolves in-process. This covers
                    // the case where the callback arrives as a plain URL open instead.
                    Task { try? await supabase.auth.session(from: url) }
                }
                .animation(.easeInOut(duration: 0.2), value: auth.state)
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(
            for: [
                WorkoutSession.self,
                ExerciseLog.self,
                ExerciseSet.self,
                WorkoutPhoto.self,
                PendingDeletion.self,
            ]
        )
    }
}
