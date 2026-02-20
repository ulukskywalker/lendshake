//
//  WelcomeView.swift
//  loandry
//
//  Created by Assistant on 2/1/26.
//

import SwiftUI
import Supabase

struct WelcomeView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Spacer()
                
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .cornerRadius(28)
                    .shadow(radius: 12)
                
                Text("Loandry")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Formalize loans with friends and family.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                
                Spacer()
                
                NavigationLink(destination: LoginView()) {
                    Text("Continue with Email")
                        .lsPrimaryButton()
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 50)
                

            }
        }
        .alert("Sign In Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }
}



#Preview {
    WelcomeView()
        .environment(AuthManager())
}
