//
//  StorageManager.swift
//  lendshake
//
//  Created by Assistant on 2/3/26.
//

import Foundation
import Supabase
import Observation

@MainActor
@Observable
class StorageManager {
    static let shared = StorageManager()
    
    private let bucketName = "proofs"
    
    func uploadProof(data: Data, userId: UUID) async throws -> String {
        let fileName = "\(UUID().uuidString).jpg"
        let path = "\(userId)/\(fileName)"
        
        // 1. Upload File to Private Bucket
        let fileOptions = FileOptions(
            cacheControl: "3600",
            contentType: "image/jpeg",
            upsert: false
        )
        
        try await supabase.storage
            .from(bucketName)
            .upload(
                path,
                data: data,
                options: fileOptions
            )
        
        // Return the full Path (e.g. "user-id/abc-123.jpg")
        return path
    }
    
    func getSignedURL(path: String) async throws -> URL? {
        let url = try await supabase.storage
            .from(bucketName)
            .createSignedURL(path: path, expiresIn: 60) // Valid for 60 seconds
        
        return url
    }
}
