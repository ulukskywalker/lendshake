//
//  SignUpView.swift
//  loandry
//
//  Created by Assistant on 2/1/26.
//

import SwiftUI

struct SignUpView: View {
    @Environment(AuthManager.self) var authManager
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    private var isFormValid: Bool {
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
            
            SecureField("Password", text: $password)
                .lsAuthInput()
            
            SecureField("Confirm Password", text: $confirmPassword)
                .lsAuthInput()
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
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
            .disabled(isLoading || !isFormValid)
            
            Spacer()
        }
        .padding()
    }
    
    private func signUp() async {
        isLoading = true
        errorMessage = nil

        guard isFormValid else {
            errorMessage = "Please fill out all fields and ensure passwords match."
            isLoading = false
            return
        }
        
        do {
            try await authManager.signUp(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    SignUpView()
        .environment(AuthManager())
}
