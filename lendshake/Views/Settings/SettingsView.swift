//
//  SettingsView.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AuthManager.self) var authManager
    
    var body: some View {
        NavigationStack {
            List {
                Button("Log Out", role: .destructive) {
                    Task {
                        try? await authManager.signOut()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthManager())
}
