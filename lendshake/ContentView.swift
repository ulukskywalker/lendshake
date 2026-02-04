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
                    Label("Home", systemImage: "house.fill")
                }
            
            SettingsView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle.fill")
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
