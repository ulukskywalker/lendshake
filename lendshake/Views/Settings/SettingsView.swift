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
    @State private var signOutError: String?
    @State private var feedbackType: FeedbackType = .general
    @State private var feedbackRating: Int = 5
    @State private var feedbackMessage = ""
    @State private var feedbackError: String?
    @State private var feedbackSuccess: String?
    @State private var isFeedbackSubmitting = false
    @State private var isFeedbackSheetPresented = false

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

                Section("Feedback") {
                    Button("Send Feedback") {
                        feedbackType = .general
                        feedbackRating = 5
                        feedbackMessage = ""
                        feedbackError = nil
                        isFeedbackSheetPresented = true
                    }
                }

                if let feedbackSuccess {
                    Section {
                        Text(feedbackSuccess)
                            .foregroundStyle(.green)
                            .font(.footnote)
                    }
                }

                Section {
                    Button("Log Out", role: .destructive) {
                        Task {
                            do {
                                try await authManager.signOut()
                            } catch {
                                signOutError = "Log out failed: \(error.localizedDescription)"
                            }
                        }
                    }
                }

                if let signOutError {
                    Section {
                        Text(signOutError)
                            .foregroundStyle(.red)
                            .font(.footnote)
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
            .sheet(isPresented: $isFeedbackSheetPresented) {
                NavigationStack {
                    Form {
                        Section("Feedback Type") {
                            Picker("Feedback Type", selection: $feedbackType) {
                                ForEach(FeedbackType.allCases) { type in
                                    Text(type.title).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Section("Rating") {
                            HStack(spacing: 10) {
                                ForEach(1...5, id: \.self) { star in
                                    Button {
                                        feedbackRating = star
                                    } label: {
                                        Image(systemName: star <= feedbackRating ? "star.fill" : "star")
                                            .font(.title3)
                                            .foregroundStyle(star <= feedbackRating ? Color.yellow : Color.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                                }
                            }
                        }

                        Section("Message") {
                            TextEditor(text: $feedbackMessage)
                                .frame(minHeight: 120)
                        }

                        if let feedbackError {
                            Section {
                                Text(feedbackError)
                                    .foregroundStyle(.red)
                                    .font(.footnote)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color.lsBackground)
                    .navigationTitle("Send Feedback")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                isFeedbackSheetPresented = false
                            }
                            .disabled(isFeedbackSubmitting)
                        }

                        ToolbarItem(placement: .confirmationAction) {
                            Button("Submit") {
                                Task { await submitFeedback() }
                            }
                            .disabled(isFeedbackSubmitting || feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
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

    private func submitFeedback() async {
        feedbackError = nil
        let message = feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            feedbackError = "Please include a short message."
            return
        }

        isFeedbackSubmitting = true
        defer { isFeedbackSubmitting = false }

        do {
            try await ReviewManager.shared.submitFeedback(type: feedbackType, rating: feedbackRating, message: message)
            feedbackSuccess = "Thanks. Your feedback was submitted."
            isFeedbackSheetPresented = false
        } catch {
            feedbackError = "Could not submit feedback: \(error.localizedDescription)"
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthManager())
        .environment(NotificationManager.shared)
}
