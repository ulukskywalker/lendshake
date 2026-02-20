//
//  AuthManager.swift
//  loandry
//
//  Created by Assistant on 2/1/26.
//

import SwiftUI
import Supabase
import Observation

@MainActor
@Observable
class AuthManager {
    static let shared = AuthManager()

    private let logger = AppLogger(.auth)
    private let service = AuthService.shared

    var isAuthenticated: Bool = false
    var isLoading: Bool = true
    var awaitingEmailConfirmation: Bool = false
    var isProfileComplete: Bool = false
    var currentUserProfile: UserProfile?
    
    private var profileNameCache: [UUID: String] = [:]
    private var inFlightProfileTasks: [UUID: Task<String?, Never>] = [:]
    
    var currentUserEmail: String? { supabase.auth.currentUser?.email }
    
    struct UserProfile: Codable {
        let first_name: String?
        let last_name: String?
        let address_line_1: String?
        let address_line_2: String?
        let residence_state: String?
        let country: String?
        let postal_code: String?
        let phone_number: String?
        let updated_at: Date?
        
        var fullName: String {
            [first_name, last_name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        }
    }
    
    init() {
        listenToAuthState()
        Task {
            await checkSession()
        }
    }
    
    // MARK: - Auth Listener
    
    private func listenToAuthState() {
        Task { @MainActor in
            _ = await supabase.auth.onAuthStateChange { [weak self] event, session in
                guard let self = self else { return }
                Task { @MainActor in
                    self.logger.info("Auth State Change: \(event)")
                    self.isAuthenticated = session != nil
                    
                    if session != nil {
                        self.awaitingEmailConfirmation = false
                        self.isLoading = false
                        try? await self.checkProfile()
                    }
                    
                    if event == .signedOut {
                        self.isAuthenticated = false
                        self.awaitingEmailConfirmation = false
                        self.currentUserProfile = nil
                        self.isProfileComplete = false
                    }
                }
            }
        }
    }
    
    // MARK: - State Orchestration
    
    func checkSession() async {
        do {
            _ = try await service.getSession()
            self.isAuthenticated = true
            try await checkProfile()
        } catch {
            self.isAuthenticated = false
            self.isProfileComplete = false
        }
        self.isLoading = false
    }
    
    func checkProfile() async throws {
        guard let user = supabase.auth.currentUser else { return }
        do {
            let profile = try await service.fetchProfile(userId: user.id)
            self.currentUserProfile = profile
            self.isProfileComplete = validateProfileCompletion(profile)
        } catch {
            logger.warning("Profile check failed: \(error.localizedDescription)")
            self.isProfileComplete = false
            self.currentUserProfile = nil
        }
    }
    
    private func validateProfileCompletion(_ p: UserProfile) -> Bool {
        let fields: [String?] = [p.first_name, p.last_name, p.address_line_1, p.residence_state, p.country, p.postal_code, p.phone_number]
        return fields.allSatisfy { $0?.trimmingCharacters(in: .whitespaces).isEmpty == false }
    }
    
    func fetchProfileName(for userId: UUID) async -> String? {
        if let cached = profileNameCache[userId] { return cached }
        if let task = inFlightProfileTasks[userId] { return await task.value }

        let task = Task<String?, Never> {
            do {
                let profile = try await service.fetchProfileName(userId: userId)
                return profile.fullName.isEmpty ? nil : profile.fullName
            } catch { return nil }
        }

        inFlightProfileTasks[userId] = task
        let name = await task.value
        inFlightProfileTasks[userId] = nil
        if let name { profileNameCache[userId] = name }
        return name
    }
    
    func createProfile(firstName: String, lastName: String, addressLine1: String, addressLine2: String?, state: String, country: String, postalCode: String, phoneNumber: String) async throws {
        guard let user = supabase.auth.currentUser else { return }
        
        struct ProfileUpdate: Encodable {
            let id: UUID; let first_name: String; let last_name: String; let address_line_1: String; let address_line_2: String?; let residence_state: String; let country: String; let postal_code: String; let phone_number: String; let updated_at: Date
        }
        
        let update = ProfileUpdate(id: user.id, first_name: firstName, last_name: lastName, address_line_1: addressLine1, address_line_2: addressLine2, residence_state: state, country: country, postal_code: postalCode, phone_number: phoneNumber, updated_at: Date())
        
        try await service.upsertProfile(AnyEncodable(update))
        try await checkProfile()
    }

    func signOut() async throws {
        try await service.signOut()
        await NotificationManager.shared.clearManagedNotifications()
        isAuthenticated = false; isProfileComplete = false; currentUserProfile = nil
    }
    
    var pendingEmail: String?

    func sendMagicLink(email: String) async throws {
        self.pendingEmail = email
        try await service.sendMagicLink(email: email)
        awaitingEmailConfirmation = true
    }
    
    func resendMagicLink() async throws {
        guard let email = pendingEmail else { return }
        try await service.sendMagicLink(email: email)
    }
    


    func handleAuthCallback(url: URL) async -> Bool {
        // Robust check for various callback formats: loandry://auth/callback or loandry://auth-callback
        let isAuthHost = url.host?.lowercased() == "auth"
        let isAuthCallbackHost = url.host?.lowercased() == "auth-callback"
        let isCallbackPath = url.path.lowercased().contains("callback")
        
        guard isAuthCallbackHost || (isAuthHost && isCallbackPath) else {
            logger.debug("URL received but not an auth callback: \(url.absoluteString)")
            return false
        }
        
        do {
            logger.info("Processing auth callback URL...")
            _ = try await service.session(from: url)
            
            // Note: listenToAuthState() will pick up the session change, 
            // but we update manually here for immediate UI feedback.
            isAuthenticated = true
            awaitingEmailConfirmation = false
            try await checkProfile()
            return true
        } catch {
            logger.error("Auth callback session extraction failed: \(error.localizedDescription)")
            return false
        }
    }
    


    func completeVerificationIfPossible() async -> Bool {
        await checkSession()
        return isAuthenticated
    }
    
    func deleteAccount() async throws {
        // Attempt to delete account via RPC (checks for active loans first)
        try await service.deleteAccount()
        // If successful, sign out locally
        try await signOut()
    }
    

}
