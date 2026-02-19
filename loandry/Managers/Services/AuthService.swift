//
//  AuthService.swift
//  loandry
//
//  Created by Assistant on 2/16/26.
//

import Foundation
import Supabase

struct AuthService {
    static let shared = AuthService()
    private init() {}
    
    func getSession() async throws -> Session {
        try await supabase.auth.session
    }
    
    func fetchProfile(userId: UUID) async throws -> AuthManager.UserProfile {
        try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .single()
            .execute()
            .value
    }
    
    func fetchProfileName(userId: UUID) async throws -> AuthManager.UserProfile {
        try await supabase
            .from("profiles")
            .select("first_name, last_name")
            .eq("id", value: userId)
            .single()
            .execute()
            .value
    }
    
    func upsertProfile(_ profile: AnyEncodable) async throws {
        try await supabase.from("profiles").upsert(profile).execute()
    }
    
    func signOut() async throws {
        try await supabase.auth.signOut()
    }
    

    
    func sendMagicLink(email: String) async throws {
        try await supabase.auth.signInWithOTP(
            email: email,
            redirectTo: URL(string: "loandry://auth/callback")
        )
    }
    

    
    func session(from url: URL) async throws -> Session {
        try await supabase.auth.session(from: url)
    }
    func deleteAccount() async throws {
        _ = try await supabase.rpc("delete_own_account").execute()
    }
}

// Helper for dynamic property names in upsert
struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) {
        _encode = value.encode
    }
    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
