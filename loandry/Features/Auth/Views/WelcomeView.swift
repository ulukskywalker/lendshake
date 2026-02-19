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
                
                Text("🤝")
                    .font(.system(size: 80))
                
                Text("Loandry")
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
                
                // OAuth Providers
                VStack(spacing: 12) {
                    // Sign in with Apple — Apple HIG: black in light, white in dark
                    Button {
                        Task {
                            do { try await authManager.signInWithProvider(.apple) }
                            catch { errorMessage = error.localizedDescription; showError = true }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.logo")
                                .font(.title3)
                            Text("Continue with Apple")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(Color(.systemBackground))
                        .background(Color(.label))
                        .cornerRadius(12)
                    }
                    
                    // Sign in with Google — Google brand: white in light, dark in dark
                    Button {
                        Task {
                            do { try await authManager.signInWithProvider(.google) }
                            catch { errorMessage = error.localizedDescription; showError = true }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            GoogleLogo()
                                .frame(width: 18, height: 18)
                            Text("Continue with Google")
                                .fontWeight(.medium)
                                .foregroundStyle(Color(.label))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                    }
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

// MARK: - Google Logo (brand-accurate multicolor G)
private struct GoogleLogo: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let cx = w / 2
            let cy = h / 2
            let r = min(w, h) / 2
            
            // Blue (right arc)
            var blue = Path()
            blue.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .degrees(-45), endAngle: .degrees(10), clockwise: false)
            blue.addLine(to: CGPoint(x: cx, y: cy))
            blue.closeSubpath()
            context.fill(blue, with: .color(Color(red: 0.259, green: 0.522, blue: 0.957)))
            
            // Green (bottom-right arc)
            var green = Path()
            green.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .degrees(10), endAngle: .degrees(120), clockwise: false)
            green.addLine(to: CGPoint(x: cx, y: cy))
            green.closeSubpath()
            context.fill(green, with: .color(Color(red: 0.204, green: 0.659, blue: 0.325)))
            
            // Yellow (bottom-left arc)
            var yellow = Path()
            yellow.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .degrees(120), endAngle: .degrees(210), clockwise: false)
            yellow.addLine(to: CGPoint(x: cx, y: cy))
            yellow.closeSubpath()
            context.fill(yellow, with: .color(Color(red: 0.984, green: 0.737, blue: 0.020)))
            
            // Red (top-left arc)
            var red = Path()
            red.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .degrees(210), endAngle: .degrees(315), clockwise: false)
            red.addLine(to: CGPoint(x: cx, y: cy))
            red.closeSubpath()
            context.fill(red, with: .color(Color(red: 0.918, green: 0.263, blue: 0.208)))
            
            // Inner circle (matches button background)
            let innerR = r * 0.55
            let inner = Path(ellipseIn: CGRect(x: cx - innerR, y: cy - innerR, width: innerR * 2, height: innerR * 2))
            context.fill(inner, with: .color(Color(.secondarySystemBackground)))
            
            // Blue bar (the horizontal stroke of the G)
            let barH = r * 0.3
            let bar = Path(CGRect(x: cx - r * 0.05, y: cy - barH / 2, width: r, height: barH))
            context.fill(bar, with: .color(Color(red: 0.259, green: 0.522, blue: 0.957)))
        }
    }
}

#Preview {
    WelcomeView()
        .environment(AuthManager())
}
