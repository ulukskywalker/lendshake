//
//  AppLogger.swift
//  lendshake
//
//  Created by Assistant on 2/9/26.
//

import Foundation
import OSLog

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
    private static let subsystem = "com.lendshake.app"

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

        guard severity == .critical else { return }
        guard let webhookURL = AppConfig.alertWebhookURL else { return }

        let dedupeKey = "\(category.rawValue)|\(summary)|\(error.localizedDescription)"
        if let lastSent = lastSentAtByKey[dedupeKey],
           Date().timeIntervalSince(lastSent) < minimumInterval {
            return
        }
        lastSentAtByKey[dedupeKey] = Date()

        var lines: [String] = []
        lines.append("*Lendshake \(severity.rawValue.capitalized) Alert*")
        lines.append("Environment: \(AppConfig.environment)")
        lines.append("Category: \(category.rawValue)")
        lines.append("Summary: \(summary)")
        lines.append("Error: \(error.localizedDescription)")

        if !metadata.isEmpty {
            let metadataLine = metadata
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            lines.append("Metadata: \(metadataLine)")
        }

        let payload = ["text": lines.joined(separator: "\n")]

        do {
            var request = URLRequest(url: webhookURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            _ = try await session.data(for: request)
            logger.info("Alert sent for \(category.rawValue)")
        } catch {
            logger.error("Failed to send alert webhook: \(error.localizedDescription)")
        }
    }
}
