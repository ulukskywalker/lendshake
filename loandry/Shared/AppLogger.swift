//
//  AppLogger.swift
//  loandry
//
//  Created by Assistant on 2/9/26.
//

import Foundation
import OSLog
import Supabase

enum AppLogCategory: String {
    case app
    case auth
    case loans
    case storage
    case notifications
    case feedback
}

enum AlertSeverity: String {
    case warning
    case critical
}

enum AppConfig {
    private static let infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]

    static var environment: String {
        (infoDictionary["APP_ENVIRONMENT"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "development"
    }

    static var alertWebhookURL: URL? {
        guard let raw = infoDictionary["ALERT_WEBHOOK_URL"] as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}

struct AppLogger {
    private static let subsystem = "com.loandry.app"

    private let logger: Logger

    init(_ category: AppLogCategory) {
        self.logger = Logger(subsystem: Self.subsystem, category: category.rawValue)
    }

    func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

@MainActor
final class AlertReporter {
    static let shared = AlertReporter()

    private let session: URLSession
    private var lastSentAtByKey: [String: Date] = [:]
    private let minimumInterval: TimeInterval = 300
    private let logger = AppLogger(.app)

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func capture(
        error: Error,
        category: AppLogCategory,
        summary: String,
        severity: AlertSeverity = .warning,
        metadata: [String: String] = [:]
    ) async {
        let scopedLogger = AppLogger(category)
        scopedLogger.error("\(summary): \(error.localizedDescription)")

        // Only alert on critical issues OR when a user sends feedback/reviews
        let isCritical = severity == .critical
        let isUserReview = category == .feedback
        
        guard isCritical || isUserReview else { return }

        // Deduplication to prevent spamming Discord
        let dedupeKey = "\(category.rawValue)|\(summary)|\(error.localizedDescription)"
        if let lastSent = lastSentAtByKey[dedupeKey],
           Date().timeIntervalSince(lastSent) < minimumInterval {
            return
        }
        lastSentAtByKey[dedupeKey] = Date()

        // Prepare payload for edge function
        struct AlertPayload: Encodable {
            let title: String
            let message: String
            let severity: String
            let metadata: [String: String]
        }

        let payload = AlertPayload(
            title: "\(category.rawValue.capitalized) Error",
            message: "\(summary)\n\nError: \(error.localizedDescription)",
            severity: severity.rawValue,
            metadata: metadata.merging(["category": category.rawValue, "env": AppConfig.environment]) { (_, new) in new }
        )

        do {
            try await supabase.functions.invoke("log-alert", options: FunctionInvokeOptions(body: payload))
            logger.info("Alert forwarded to Supabase for \(category.rawValue)")
        } catch {
            logger.error("Failed to forward alert to Supabase: \(error.localizedDescription)")
            
            // Fallback to direct alert if webhook is configured (legacy support)
            if severity == .critical, let webhookURL = AppConfig.alertWebhookURL {
                await sendDirectWebhook(lines: [
                    "*Loandry Fallback Alert*",
                    "Summary: \(summary)",
                    "Error: \(error.localizedDescription)"
                ], url: webhookURL)
            }
        }
    }

    private func sendDirectWebhook(lines: [String], url: URL) async {
        let payload = ["text": lines.joined(separator: "\n")]
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            _ = try await session.data(for: request)
        } catch {
            logger.error("Fallback webhook failed: \(error.localizedDescription)")
        }
    }
}
