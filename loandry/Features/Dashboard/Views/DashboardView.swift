//
//  DashboardView.swift
//  loandry
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()
    @State private var showSettingsSheet = false
    @Environment(AppRouter.self) var appRouter
    @Environment(NotificationManager.self) var notificationManager
    @AppStorage("notifications.prompted") private var didPromptForNotifications = false
    
    var body: some View {
        ZStack {
            NavigationStack {
                LoanListView(
                    selectedLoan: Binding(
                        get: { viewModel.selectedLoan },
                        set: { viewModel.selectedLoan = $0 }
                    )
                )
                .navigationBarHidden(true)
                .task {
                    if !didPromptForNotifications {
                        _ = await notificationManager.requestAuthorizationIfNeeded()
                        didPromptForNotifications = true
                    }
                    await viewModel.onAppear()
                }
                .refreshable {
                    await viewModel.onRefresh()
                }

                .onChange(of: LoanManager.shared.loans.count) { _, _ in
                    viewModel.handleDeepLink(route: appRouter.pendingRoute)
                    if appRouter.pendingRoute != nil {
                        _ = appRouter.consumeRoute()
                    }
                    viewModel.checkSelectedLoanExists()
                }
                .onChange(of: appRouter.pendingRoute != nil) { _, _ in
                    viewModel.handleDeepLink(route: appRouter.pendingRoute)
                    if appRouter.pendingRoute != nil {
                        _ = appRouter.consumeRoute()
                    }
                }
                .sheet(isPresented: $viewModel.showCreateSheet) {
                    NavigationStack {
                        LoanConstructionView(onLoanCreated: { newLoan in
                            viewModel.onLoanCreated(newLoan: newLoan)
                        })
                    }
                }
                .sheet(isPresented: $showSettingsSheet) {
                    NavigationStack {
                        SettingsView()
                    }
                }
            }
            
            // ── Floating top buttons (covered by expanded card) ──
            VStack {
                HStack {
                    Button {
                        showSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    }
                    
                    Spacer()
                    
                    Button {
                        viewModel.showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    }
                }
                .padding(.horizontal, 12)
                
                Spacer()
            }
            .zIndex(viewModel.selectedLoan == nil ? 1 : -1)
        }
        .overlay(alignment: .top) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding()
                    .background(Color.red.cornerRadius(8))
                    .padding(.top)
                    .transition(.move(edge: .top))
                    .onTapGesture {
                        viewModel.errorMessage = nil
                    }
            }
        }
    }
}
    
#Preview {
    DashboardView()
        .environment(LoanManager.shared)
        .environment(AuthManager.shared)
        .environment(AppRouter())
        .environment(NotificationManager.shared)
}
