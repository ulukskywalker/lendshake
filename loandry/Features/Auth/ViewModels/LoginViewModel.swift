//
//  LoginViewModel.swift
//  loandry
//
//  Created by Assistant on 2/18/26.
//

import SwiftUI
import Observation

@MainActor
@Observable
class LoginViewModel {
    var email = ""
    var password = ""
    var errorMessage: String?
    var isLoading = false
    
    var isValid: Bool {
        !email.isEmpty && !password.isEmpty
    }
    
    private let authManager: AuthManager
    
    init(authManager: AuthManager) {
        self.authManager = authManager
    }
    
    // Convenience init for previews/default usage, must be MainActor
    convenience init() {
        self.init(authManager: AuthManager.shared)
    }
    
    func signIn() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await authManager.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}
