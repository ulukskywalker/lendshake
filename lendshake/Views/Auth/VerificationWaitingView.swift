//
//  VerificationWaitingView.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct VerificationWaitingView: View {
    @Environment(AuthManager.self) var authManager
    @State private var isChecking = false
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
            
            Text("Check your email")
                .font(.largeTitle)
                .bold()
            
            Text("We've sent a confirmation link to your inbox. Please verify your email to continue.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Spacer()
            
            Button {
                Task {
                    isChecking = true
                    await authManager.checkSession()
                    
                    if !authManager.isAuthenticated {
                        // If no session found (because deep link was skipped),
                        // we must ask the user to Sign In manually.
                        authManager.awaitingEmailConfirmation = false
                    }
                    isChecking = false
                }
            } label: {
                if isChecking {
                    ProgressView()
                } else {
                    Text("I've Verified")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .disabled(isChecking)
            
            Button("Cancel / Back to Sign In") {
                authManager.awaitingEmailConfirmation = false
                authManager.isAuthenticated = false
            }
            .padding(.top, 10)
            
            Spacer().frame(height: 20)
        }
        .padding()
    }
}

#Preview {
    VerificationWaitingView()
        .environment(AuthManager())
}
