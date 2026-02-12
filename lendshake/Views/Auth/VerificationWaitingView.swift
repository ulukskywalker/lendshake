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
    @State private var statusMessage: String?
    
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

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            Button {
                Task {
                    isChecking = true
                    statusMessage = nil
                    let completed = await authManager.completeVerificationIfPossible()
                    if !completed {
                        statusMessage = "Open the verification link from the same device to finish sign in."
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
