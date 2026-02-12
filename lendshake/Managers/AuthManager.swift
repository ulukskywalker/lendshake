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
    private let logger = AppLogger(.auth)

    var isAuthenticated: Bool = false
    var isLoading: Bool = true
    var awaitingEmailConfirmation: Bool = false
    var isProfileComplete: Bool = false
    var currentUserProfile: UserProfile?
    private var profileNameCache: [UUID: String] = [:]
    private var missingProfileNameIDs: Set<UUID> = []
    private var inFlightProfileNameTasks: [UUID: Task<String?, Never>] = [:]
    private var pendingVerificationEmail: String?
    private var pendingVerificationPassword: String?
    var currentUserEmail: String? {
        supabase.auth.currentUser?.email
    }
    
    // Simple User Profile struct for decoding
    struct UserProfile: Decodable {
        let first_name: String?
        let last_name: String?
        let address_line_1: String?
        let address_line_2: String?
        let residence_state: String? // Added state
        let country: String?
        let postal_code: String?
        let phone_number: String? // Added phone number
        let updated_at: Date?
        
        var fullName: String {
            [first_name, last_name].compactMap { $0 }.joined(separator: " ")
        }
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
        do {
            let profile: UserProfile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: user.id)
                .single()
                .execute()
                .value
            
            self.currentUserProfile = profile
            
            if let first = profile.first_name, !first.isEmpty,
               let last = profile.last_name, !last.isEmpty,
               let address = profile.address_line_1, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let state = profile.residence_state, state.count == 2,
               let country = profile.country, !country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let postal = profile.postal_code, !postal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let phone = profile.phone_number, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.isProfileComplete = true
            } else {
                self.isProfileComplete = false
            }
        } catch {
            logger.warning("Profile check failed: \(error.localizedDescription)")
            self.isProfileComplete = false
            self.currentUserProfile = nil
        }
    }
    
    func fetchProfileName(for userId: UUID) async -> String? {
        if let cached = profileNameCache[userId] {
            return cached
        }
        if missingProfileNameIDs.contains(userId) {
            return nil
        }
        if let task = inFlightProfileNameTasks[userId] {
            return await task.value
        }

        let task = Task<String?, Never> {
            do {
                let profile: UserProfile = try await supabase
                    .from("profiles")
                    .select("first_name, last_name")
                    .eq("id", value: userId)
                    .single()
                    .execute()
                    .value

                let fullName = profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                return fullName.isEmpty ? nil : fullName
            } catch {
                return nil
            }
        }

        inFlightProfileNameTasks[userId] = task
        let resolvedName = await task.value
        inFlightProfileNameTasks[userId] = nil

        if let resolvedName {
            profileNameCache[userId] = resolvedName
            return resolvedName
        } else {
            missingProfileNameIDs.insert(userId)
            return nil
        }
    }
    
    func createProfile(
        firstName: String,
        lastName: String,
        addressLine1: String,
        addressLine2: String?,
        state: String,
        country: String,
        postalCode: String,
        phoneNumber: String
    ) async throws {
        guard let user = supabase.auth.currentUser else { return }
        
        struct ProfileUpdate: Encodable {
            let id: UUID
            let first_name: String
            let last_name: String
            let address_line_1: String
            let address_line_2: String?
            let residence_state: String
            let country: String
            let postal_code: String
            let phone_number: String
            let updated_at: Date
        }
        
        let update = ProfileUpdate(
            id: user.id,
            first_name: firstName,
            last_name: lastName,
            address_line_1: addressLine1,
            address_line_2: addressLine2,
            residence_state: state,
            country: country,
            postal_code: postalCode,
            phone_number: phoneNumber,
            updated_at: Date()
        )
        
        // Upsert the profile
        try await supabase.from("profiles").upsert(update).execute()
        
        self.isProfileComplete = true
        // Refresh local profile
        try await checkProfile()
    }

    func signOut() async throws {
        try await supabase.auth.signOut()
        await NotificationManager.shared.clearManagedNotifications()
        self.isAuthenticated = false
        self.isProfileComplete = false
        self.currentUserProfile = nil
        self.pendingVerificationEmail = nil
        self.pendingVerificationPassword = nil
    }
    
    func signIn(email: String, password: String) async throws {
        _ = try await supabase.auth.signIn(email: email, password: password)
        self.awaitingEmailConfirmation = false
        self.isAuthenticated = true
        await checkSession()
        self.pendingVerificationEmail = nil
        self.pendingVerificationPassword = nil
    }
    
    func signUp(email: String, password: String) async throws {
        do {
            let redirectURL = URL(string: "lendshake://auth/callback")
            _ = try await supabase.auth.signUp(
                email: email,
                password: password,
                redirectTo: redirectURL
            )
            self.awaitingEmailConfirmation = true
            self.pendingVerificationEmail = email
            self.pendingVerificationPassword = password
        } catch {
            await AlertReporter.shared.capture(
                error: error,
                category: .auth,
                summary: "User sign up failed",
                severity: .warning,
                metadata: ["email_domain": email.components(separatedBy: "@").last ?? "unknown"]
            )
            throw error
        }
    }

    func handleAuthCallback(url: URL) async -> Bool {
        guard let host = url.host?.lowercased(), host == "auth" else { return false }
        let path = url.path.lowercased()
        guard path.contains("callback") else { return false }

        do {
            _ = try await supabase.auth.session(from: url)
            awaitingEmailConfirmation = false
            isAuthenticated = true
            try await checkProfile()
            pendingVerificationEmail = nil
            pendingVerificationPassword = nil
            return true
        } catch {
            logger.warning("Auth callback handling failed: \(error.localizedDescription)")
            return false
        }
    }

    func completeVerificationIfPossible() async -> Bool {
        await checkSession()
        if isAuthenticated {
            awaitingEmailConfirmation = false
            pendingVerificationEmail = nil
            pendingVerificationPassword = nil
            return true
        }

        guard let email = pendingVerificationEmail, let password = pendingVerificationPassword else {
            return false
        }

        do {
            _ = try await supabase.auth.signIn(email: email, password: password)
            awaitingEmailConfirmation = false
            isAuthenticated = true
            try await checkProfile()
            pendingVerificationEmail = nil
            pendingVerificationPassword = nil
            return true
        } catch {
            logger.info("Verification completion sign-in not ready: \(error.localizedDescription)")
            return false
        }
    }
}
