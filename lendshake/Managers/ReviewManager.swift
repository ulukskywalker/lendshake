//
//  ReviewManager.swift
//  lendshake
//
//  Created by Assistant on 2/9/26.
//

import Foundation
import StoreKit
import UIKit
import Supabase

enum FeedbackType: String, CaseIterable, Identifiable {
    case general
    case bug
    case feature

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .bug:
            return "Bug report"
        case .feature:
            return "Feature request"
        }
    }
}

@MainActor
final class ReviewManager {
    static let shared = ReviewManager()

    private let logger = AppLogger(.feedback)

    private init() {}

    func requestAppStoreReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            logger.warning("Could not request review: no active scene")
            return
        }

        AppLogger(.feedback).info("Requesting App Store review prompt")
        if #available(iOS 18.0, *) {
            AppStore.requestReview(in: scene)
        } else {
            SKStoreReviewController.requestReview(in: scene)
        }
    }

    func submitFeedback(type: FeedbackType, rating: Int?, message: String) async throws {
        struct FeedbackInsert: Encodable {
            let user_id: UUID
            let feedback_type: String
            let rating: Int?
            let message: String
            let app_version: String?
            let os_version: String
            let created_at: Date
        }

        guard let currentUser = supabase.auth.currentUser else {
            throw AuthError.notAuthenticated
        }

        let payload = FeedbackInsert(
            user_id: currentUser.id,
            feedback_type: type.rawValue,
            rating: rating,
            message: message,
            app_version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            os_version: UIDevice.current.systemVersion,
            created_at: Date()
        )

        do {
            try await supabase
                .from("app_feedback")
                .insert(payload)
                .execute()
            logger.info("Feedback submitted: type=\(type.rawValue)")
        } catch {
            await AlertReporter.shared.capture(
                error: error,
                category: .feedback,
                summary: "Failed to submit feedback",
                severity: .warning
            )
            throw error
        }
    }
}
