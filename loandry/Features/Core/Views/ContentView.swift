//
//  ContentView.swift
//  loandry
//
//  Created by Uluk Abylbekov on 2/1/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(LoanManager.self) private var loanManager
    @Environment(AuthManager.self) private var authManager
    @Environment(NotificationManager.self) private var notificationManager

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .badge(loanManager.requiredActionCount)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(.blue)
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
        .environment(LoanManager())
        .environment(NotificationManager.shared)
}
