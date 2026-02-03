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
                ProgressView()
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

#Preview {
    RootView()
        .environment(AuthManager())
}
