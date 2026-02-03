//
//  AuthManager.swift
//  lendshake
//
//  Created by Assistant on 2/1/26.
//

import SwiftUI
import Supabase
import Observation

@MainActor
@Observable
class AuthManager {
    var isAuthenticated: Bool = false
    var isLoading: Bool = true
    var awaitingEmailConfirmation: Bool = false
    var isProfileComplete: Bool = false
    
    // Simple User Profile struct for decoding
    struct UserProfile: Decodable {
        let first_name: String?
        let last_name: String?
    }
    
    init() {
        Task {
            await checkSession()
        }
    }
    
    func checkSession() async {
        do {
            // session property is async and throwing
            _ = try await supabase.auth.session
            self.isAuthenticated = true
            
            // Check Profile
            try await checkProfile()
            
        } catch {
            self.isAuthenticated = false
            self.isProfileComplete = false
        }
        self.isLoading = false
    }
    
    func checkProfile() async throws {
        guard let user = supabase.auth.currentUser else { return }
        
        // Fetch profile row
        // Assuming table 'profiles' with 'id' matching user.id
        // We select 'first_name' and 'last_name' to check if they are set
        do {
            let profile: UserProfile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: user.id)
                .single()
                .execute()
                .value
            
            if let first = profile.first_name, !first.isEmpty,
               let last = profile.last_name, !last.isEmpty {
                self.isProfileComplete = true
            } else {
                self.isProfileComplete = false
            }
        } catch {
            // Profile row typically auto-created by triggers, or might not exist.
            // If error, assume incomplete.
            print("Profile check error: \(error)")
            self.isProfileComplete = false
        }
    }
    
    func createProfile(firstName: String, lastName: String, state: String) async throws {
        guard let user = supabase.auth.currentUser else { return }
        
        struct ProfileUpdate: Encodable {
            let id: UUID
            let first_name: String
            let last_name: String
            let residence_state: String
            let updated_at: Date
        }
        
        let update = ProfileUpdate(
            id: user.id,
            first_name: firstName,
            last_name: lastName,
            residence_state: state,
            updated_at: Date()
        )
        
        // Upsert the profile
        try await supabase.from("profiles").upsert(update).execute()
        
        self.isProfileComplete = true
    }
    
    func signOut() async throws {
        try await supabase.auth.signOut()
        self.isAuthenticated = false
    }
    
    func signIn(email: String, password: String) async throws {
        _ = try await supabase.auth.signIn(email: email, password: password)
        self.isAuthenticated = true
    }
    
    func signUp(email: String, password: String) async throws {
        do {
            _ = try await supabase.auth.signUp(email: email, password: password)
            // Implicitly assume success means email sent.
            // Supabase returns a session if "Confirm Email" is disabled, but nil/user if enabled.
            // We'll set waiting state regardless? No, let's check.
            // Actually, for this flow, we FORCE the user to see the verification screen.
            self.awaitingEmailConfirmation = true
        } catch {
            print("DEBUG: Sign Up Error: \(error)")
            throw error
        }
    }
}
