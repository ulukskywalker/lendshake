//
//  NotificationManager.swift
//  lendshake
//
//  Created by Assistant on 2/8/26.
//

import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let logger = AppLogger(.notifications)

    private let center = UNUserNotificationCenter.current()
    private let managedPrefix = "loan.event."
    private let actionNotificationsEnabledKey = "notifications.actions.enabled"

    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var actionNotificationsEnabled: Bool

    var notificationsEnabledInSystem: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    private override init() {
        actionNotificationsEnabled = UserDefaults.standard.object(forKey: actionNotificationsEnabledKey) as? Bool ?? true
        super.init()
        center.delegate = self
        Task { await refreshAuthorizationStatus() }
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        await refreshAuthorizationStatus()
        if notificationsEnabledInSystem { return true }
        if authorizationStatus == .denied { return false }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            await refreshAuthorizationStatus()
            return false
        }
    }

    func setActionNotificationsEnabled(_ enabled: Bool) {
        actionNotificationsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: actionNotificationsEnabledKey)
    }

    func clearManagedNotifications() async {
        let pending = await pendingRequests()
        let ids = pending
            .filter { $0.identifier.hasPrefix(managedPrefix) }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func postEventNotification(eventID: String, title: String, body: String, deepLink: String? = nil) async {
        await refreshAuthorizationStatus()

        guard actionNotificationsEnabled, notificationsEnabledInSystem else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let deepLink, !deepLink.isEmpty {
            content.userInfo["deep_link"] = deepLink
        }

        let request = UNNotificationRequest(
            identifier: managedPrefix + eventID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
        do {
            try await add(request: request)
        } catch {
            logger.warning("Notification post failed (\(request.identifier)): \(error.localizedDescription)")
        }
    }

    private func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    private func add(request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let deepLink = userInfo["deep_link"] as? String, let url = URL(string: deepLink) {
            Task { @MainActor in
                AppRouter.shared.handle(url: url)
                completionHandler()
            }
            return
        }
        completionHandler()
    }
}
