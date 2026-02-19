//
//  SettingsView.swift
//  loandry
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(NotificationManager.self) private var notificationManager
    
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
    @State private var showDeleteConfirmation = false
    @State private var deleteConfirmationText = ""

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
                        prepareFeedback()
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
                        Task { await signOut() }
                    }
                    
                    Button("Delete Account", role: .destructive) {
                        showDeleteConfirmation = true
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
            .background(Color.appBackground)
            .navigationTitle("Settings")
            .task {
                actionNotificationsEnabled = notificationManager.actionNotificationsEnabled
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
                    .background(Color.appBackground)
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
        .sensoryFeedback(.success, trigger: feedbackSuccess) { _, newValue in newValue != nil }
        .sensoryFeedback(.error, trigger: feedbackError) { _, newValue in newValue != nil }
        .sensoryFeedback(.error, trigger: signOutError) { _, newValue in newValue != nil }
        .alert("Delete Account", isPresented: $showDeleteConfirmation) {
            TextField("Type 'Delete Account'", text: $deleteConfirmationText)
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if deleteConfirmationText == "Delete Account" {
                    performDeleteAccount()
                }
            }
            .disabled(deleteConfirmationText != "Delete Account")
        } message: {
            Text("This action cannot be undone. Type 'Delete Account' to confirm.")
        }
        .onChange(of: showDeleteConfirmation) { _, isPresented in
            if isPresented { deleteConfirmationText = "" }
        }
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
    
    private func prepareFeedback() {
        feedbackType = .general
        feedbackRating = 5
        feedbackMessage = ""
        feedbackError = nil
        isFeedbackSheetPresented = true
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
            try await ReviewService.shared.submitFeedback(type: feedbackType, rating: feedbackRating, message: message)
            feedbackSuccess = "Thanks. Your feedback was submitted."
            isFeedbackSheetPresented = false
        } catch {
            feedbackError = "Could not submit feedback: \(error.localizedDescription)"
        }
    }
    
    private func performDeleteAccount() {
        signOutError = nil
        Task {
            do {
                try await authManager.deleteAccount()
            } catch {
                signOutError = "Deletion Failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func signOut() async {
        do {
            try await authManager.signOut()
        } catch {
            signOutError = "Log out failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthManager())
        .environment(NotificationManager.shared)
}
