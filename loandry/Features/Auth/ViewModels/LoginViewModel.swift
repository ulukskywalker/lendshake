
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
    var errorMessage: String?
    var isLoading = false
    
    var isValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private let authManager: AuthManager
    
    init(authManager: AuthManager) {
        self.authManager = authManager
    }
    
    convenience init() {
        self.init(authManager: AuthManager.shared)
    }
    
    func sendMagicLink() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await authManager.sendMagicLink(email: email)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}
