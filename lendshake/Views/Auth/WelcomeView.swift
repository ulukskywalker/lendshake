//
//  WelcomeView.swift
//  lendshake
//
//  Created by Assistant on 2/1/26.
//

import SwiftUI

struct WelcomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Spacer()
                
                Image(systemName: "hand.wave.fill") // Placeholder icon
                    .font(.system(size: 80))
                    .foregroundStyle(.tint)
                
                Text("Lendshake")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Formalize loans with friends and family.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                
                Spacer()
                
                VStack(spacing: 16) {
                    NavigationLink(destination: LoginView()) {
                        Text("Sign In")
                            .lsPrimaryButton()
                    }
                    
                    NavigationLink(destination: SignUpView()) {
                        Text("Create Account")
                            .lsSecondaryButton()
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 50)
            }
        }
    }
}

#Preview {
    WelcomeView()
        .environment(AuthManager())
}
