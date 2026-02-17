//
//  SignUpView.swift
//  loandry
//
//  Created by Assistant on 2/1/26.
//

import SwiftUI

struct SignUpView: View {
    @Environment(AuthManager.self) private var authManager
    
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    private var isValid: Bool {
        !email.isEmpty && !password.isEmpty && password == confirmPassword
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create Account")
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
            
            SecureField("Confirm Password", text: $confirmPassword)
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
                    await signUp()
                }
            } label: {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .lsPrimaryButton(background: .green)
                } else {
                    Text("Sign Up")
                        .lsPrimaryButton(background: .green)
                }
            }
            .disabled(isLoading || !isValid)
            .animation(.easeInOut, value: isLoading)
            
            Spacer()
        }
        .padding()
    }
    
    private func signUp() async {
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
            HapticUtility.notification(.error)
        }
        
        isLoading = false
    }
}

#Preview {
    SignUpView()
        .environment(AuthManager())
}
