//
//  loandryApp.swift
//  loandry
//
//  Created by Uluk Abylbekov on 2/1/26.
//

import SwiftUI

@main
@MainActor
struct loandryApp: App {
    @State private var authManager = AuthManager.shared
    @State private var loanManager = LoanManager.shared
    @State private var notificationManager = NotificationManager.shared
    @State private var appRouter = AppRouter.shared
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authManager)
                .environment(loanManager)
                .environment(notificationManager)
                .environment(appRouter)
        }
    }
}
