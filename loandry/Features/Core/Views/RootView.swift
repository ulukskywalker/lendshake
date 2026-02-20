//
//  RootView.swift
//  loandry
//
//  Created by Assistant on 2/1/26.
//

import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) var authManager
    @Environment(NotificationManager.self) var notificationManager
    @Environment(AppRouter.self) var appRouter

    
    var body: some View {
        Group {
            if authManager.isLoading {
                SplashLoadingView()

            } else if authManager.isAuthenticated {
                ContentView()
            } else if authManager.awaitingEmailConfirmation {
                VerificationWaitingView()
            } else {
                WelcomeView()
            }
        }

        .onOpenURL { url in
            Task {
                if await authManager.handleAuthCallback(url: url) {
                    return
                }
                await MainActor.run {
                    appRouter.handle(url: url)
                }
            }
        }
    }
}

private struct SplashLoadingView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.blue.opacity(0.2), Color.appBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .cornerRadius(22)
                    .shadow(radius: 10)

                Text("Loandry")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                ProgressView("Loading...")
                    .tint(Color.blue)
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
