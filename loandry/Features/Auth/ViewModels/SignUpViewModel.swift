//
//  SignUpViewModel.swift
//  loandry
//
//  Created by Assistant on 2/18/26.
//

import SwiftUI
import Observation

@MainActor
@Observable
class SignUpViewModel {
    var email = ""
    var password = ""
    var confirmPassword = ""
    var errorMessage: String?
    var isLoading = false
    
    var isValid: Bool {
        !email.isEmpty && !password.isEmpty && password == confirmPassword
    }
    
    private let authManager: AuthManager
    
    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    convenience init() {
        self.init(authManager: AuthManager.shared)
    }
    
    func signUp() async {
        guard isValid else {
            errorMessage = "Please fill out all fields and ensure passwords match."
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            try await authManager.signUp(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}
