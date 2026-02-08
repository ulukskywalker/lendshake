//
//  RootView.swift
//  lendshake
//
//  Created by Assistant on 2/1/26.
//

import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) var authManager
    @Environment(NotificationManager.self) var notificationManager
    @AppStorage("notifications.prompted.on.launch") private var didPromptForNotifications = false
    
    var body: some View {
        Group {
            if authManager.isLoading {
                SplashLoadingView()
            } else if authManager.isAuthenticated {
                if authManager.isProfileComplete {
                    ContentView()
                } else {
                    ProfileSetupView()
                }
            } else if authManager.awaitingEmailConfirmation {
                VerificationWaitingView()
            } else {
                WelcomeView()
            }
        }
        .task {
            guard !didPromptForNotifications else { return }
            _ = await notificationManager.requestAuthorizationIfNeeded()
            didPromptForNotifications = true
        }
    }
}

private struct SplashLoadingView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.lsPrimary.opacity(0.2), Color.lsBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(Color.lsPrimary)

                Text("Lendshake")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                ProgressView("Loading...")
                    .tint(Color.lsPrimary)
            }
            .padding(24)
        }
    }
}

#Preview {
    RootView()
        .environment(AuthManager())
        .environment(NotificationManager.shared)
}
