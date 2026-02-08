//
//  lendshakeApp.swift
//  lendshake
//
//  Created by Uluk Abylbekov on 2/1/26.
//

import SwiftUI

@main
struct lendshakeApp: App {
    @State private var authManager = AuthManager()
    @State private var loanManager = LoanManager()
    @State private var notificationManager = NotificationManager.shared
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authManager)
                .environment(loanManager)
                .environment(notificationManager)
        }
    }
}
