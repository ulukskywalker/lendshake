
//
//  VerificationWaitingViewModel.swift
//  loandry
//
//  Created by Assistant on 2/18/26.
//

import SwiftUI
import Observation

@MainActor
@Observable
class VerificationWaitingViewModel {
    var isResending = false
    var statusMessage: String?
    
    private let authManager: AuthManager
    
    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    convenience init() {
        self.init(authManager: AuthManager.shared)
    }
    
    func resendVerification() async {
        guard !isResending else { return }
        
        if authManager.pendingEmail == nil {
            statusMessage = "Session expired. Please sign in again."
            return
        }

        isResending = true
        statusMessage = "Sending..."
        
        do {
            try await authManager.resendMagicLink()
            statusMessage = "Sent! Check your inbox."
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
        
        isResending = false
    }
    
    func cancel() {
        authManager.awaitingEmailConfirmation = false
        authManager.isAuthenticated = false
    }

    func checkStatus() async {
        statusMessage = "Checking..."
        let success = await authManager.completeVerificationIfPossible()
        if !success {
            statusMessage = "Verification link not clicked yet."
        }
    }
}
