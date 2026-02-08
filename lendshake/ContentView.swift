//
//  ContentView.swift
//  lendshake
//
//  Created by Uluk Abylbekov on 2/1/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(LoanManager.self) var loanManager

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
        .tint(.lsPrimary)
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
        .environment(LoanManager())
}
