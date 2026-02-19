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
            triggerSuccessHaptic.toggle()
        }
        
        isChecking = false
    }
    
    func cancel() {
        authManager.awaitingEmailConfirmation = false
        authManager.isAuthenticated = false
    }
}
