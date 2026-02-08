//
//  RootView.swift
//  lendshake
//
//  Created by Assistant on 2/1/26.
//

import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) var authManager
    
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
}
