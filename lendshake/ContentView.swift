//
//  ContentView.swift
//  lendshake
//
//  Created by Uluk Abylbekov on 2/1/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("My Lends", systemImage: "banknote")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
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
