//
//  LoginView.swift
//  loandry
//
//  Created by Assistant on 2/1/26.
//

import SwiftUI

struct LoginView: View {
    @Environment(AuthManager.self) private var authManager
    
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    private var isValid: Bool {
        !email.isEmpty && !password.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Sign In")
                .font(.largeTitle)
                .bold()
            
            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .lsAuthInput()
                .disabled(isLoading)
            
            SecureField("Password", text: $password)
                .lsAuthInput()
                .disabled(isLoading)
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .transition(.opacity)
            }
            
            Button {
                Task {
                    await signIn()
                }
            } label: {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .lsPrimaryButton()
                } else {
                    Text("Sign In")
                        .lsPrimaryButton()
                }
            }
            .disabled(isLoading || !isValid)
            .animation(.easeInOut, value: isLoading)
            
            Spacer()
        }
        .padding()
    }
    
    private func signIn() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await authManager.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
            HapticUtility.notification(.error)
        }
        
        isLoading = false
    }
}

#Preview {
    LoginView()
        .environment(AuthManager())
}
