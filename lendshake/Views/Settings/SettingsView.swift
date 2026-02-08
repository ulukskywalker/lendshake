//
//  SettingsView.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AuthManager.self) var authManager
    @Environment(NotificationManager.self) var notificationManager
    
    @State private var actionNotificationsEnabled = false
    @State private var notificationError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    NavigationLink {
                        AccountView()
                    } label: {
                        Label("Profile", systemImage: "person.crop.circle")
                    }
                }
                
                Section("Notifications") {
                    Toggle("Action Notifications", isOn: $actionNotificationsEnabled)

                    LabeledContent("System Notifications", value: notificationStatusText)
                        .foregroundStyle(notificationManager.notificationsEnabledInSystem ? Color.secondary : Color.orange)
                }
                
                if let notificationError {
                    Section {
                        Text(notificationError)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button("Log Out", role: .destructive) {
                        Task {
                            try? await authManager.signOut()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.lsBackground)
            .navigationTitle("Settings")
            .task {
                loadNotificationSettings()
                await notificationManager.refreshAuthorizationStatus()
            }
            .onChange(of: actionNotificationsEnabled) { _, newValue in
                Task { await applyNotificationToggle(enabled: newValue) }
            }
        }
    }
    
    private func loadNotificationSettings() {
        actionNotificationsEnabled = notificationManager.actionNotificationsEnabled
    }
    
    private func applyNotificationToggle(enabled: Bool) async {
        notificationError = nil
        if enabled {
            let granted = await notificationManager.requestAuthorizationIfNeeded()
            guard granted else {
                notificationError = "Notifications are disabled in iOS Settings."
                actionNotificationsEnabled = false
                notificationManager.setActionNotificationsEnabled(false)
                return
            }
        }

        notificationManager.setActionNotificationsEnabled(enabled)
        if !enabled {
            await notificationManager.clearManagedNotifications()
        }
    }
    
    private var notificationStatusText: String {
        switch notificationManager.authorizationStatus {
        case .authorized:
            return "Allowed"
        case .provisional:
            return "Provisional"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not Requested"
        case .ephemeral:
            return "Ephemeral"
        @unknown default:
            return "Unknown"
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthManager())
        .environment(NotificationManager.shared)
}
