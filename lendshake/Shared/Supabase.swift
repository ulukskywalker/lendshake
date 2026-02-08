//
//  Supabase.swift
//  lendshake
//
//  Created by Assistant on 2/1/26.
//

import Foundation
import Supabase

enum APIConfig {
    private static let infoDictionary: [String: Any] = {
        guard let dict = Bundle.main.infoDictionary else {
            fatalError("Plist file not found")
        }
        return dict
    }()
    
    static let supabaseURL: URL = {
        guard let string = infoDictionary["SUPABASE_URL"] as? String,
              let url = URL(string: string) else {
            fatalError("Supabase URL missing or invalid")
        }
        if url.host == nil {
             fatalError("Supabase URL is invalid (no host). Value loaded: '\(string)'. Check Info.plist and xcconfig.")
        }
        return url
    }()
    
    static let supabaseKey: String = {
        guard let key = infoDictionary["SUPABASE_KEY"] as? String else {
            fatalError("Supabase Key missing")
        }
        return key
    }()
}

// Initialization
let supabase = SupabaseClient(
    supabaseURL: APIConfig.supabaseURL,
    supabaseKey: APIConfig.supabaseKey,
)
