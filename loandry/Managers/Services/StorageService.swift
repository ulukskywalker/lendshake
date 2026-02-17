//
//  StorageService.swift
//  loandry
//
//  Created by Assistant on 2/16/26.
//

import Foundation
import Supabase

struct StorageService {
    static let shared = StorageService()
    private init() {}
    
    private let bucketName = "proofs"
    
    func uploadProof(data: Data, userId: UUID) async throws -> String {
        let fileName = "\(UUID().uuidString).jpg"
        let path = "\(userId)/\(fileName)"
        
        let fileOptions = FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: false)
        
        try await supabase.storage
            .from(bucketName)
            .upload(path, data: data, options: fileOptions)
        
        return path
    }
    
    func getSignedURL(path: String) async throws -> URL? {
        try await supabase.storage
            .from(bucketName)
            .createSignedURL(path: path, expiresIn: 60)
    }
}
