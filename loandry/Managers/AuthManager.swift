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
        Task { await checkSession() }
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
    
    func signIn(email: String, password: String) async throws {
        try await service.signIn(email: email, password: password)
        awaitingEmailConfirmation = false; isAuthenticated = true
        await checkSession()
    }
    
    func signUp(email: String, password: String) async throws {
        let redirectURL = URL(string: "loandry://auth/callback")
        try await service.signUp(email: email, password: password, redirectTo: redirectURL)
        awaitingEmailConfirmation = true
    }

    func handleAuthCallback(url: URL) async -> Bool {
        guard url.host?.lowercased() == "auth", url.path.lowercased().contains("callback") else { return false }
        do {
            _ = try await service.session(from: url)
            awaitingEmailConfirmation = false; isAuthenticated = true
            try await checkProfile()
            return true
        } catch {
            logger.warning("Auth callback failed: \(error.localizedDescription)")
            return false
        }
    }

    func completeVerificationIfPossible() async -> Bool {
        await checkSession()
        return isAuthenticated
    }
}
