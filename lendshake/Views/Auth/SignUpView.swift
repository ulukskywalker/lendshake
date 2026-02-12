//
//  SignUpView.swift
//  lendshake
//
//  Created by Assistant on 2/1/26.
//

import SwiftUI

struct SignUpView: View {
    @Environment(AuthManager.self) var authManager
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    
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
            .disabled(isLoading || email.isEmpty || password.isEmpty)
            
            Spacer()
        }
        .padding()
    }
    
    private func signUp() async {
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

#Preview {
    SignUpView()
        .environment(AuthManager())
}
