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
    var isChecking = false
    var isResending = false
    var statusMessage: String?
    
    private let authManager: AuthManager
    
    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    convenience init() {
        self.init(authManager: AuthManager.shared)
    }
    
    var triggerSuccessHaptic = false
    
    func checkVerification() async {
        isChecking = true
        statusMessage = nil
        
        let completed = await authManager.completeVerificationIfPossible()
        
        if !completed {
            statusMessage = "Open the verification link from the same device to finish sign in."
        } else {
            triggerSuccessHaptic.toggle() // The observable property
        }
        
        isChecking = false
    }

    func resendVerification() async {
        guard !isResending else { return }
        
        if authManager.currentUserEmail == nil {
            statusMessage = "Session expired. Please sign in again."
            return
        }

        isResending = true
        statusMessage = "Sending..."
        
        do {
            try await authManager.resendVerification()
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
}
