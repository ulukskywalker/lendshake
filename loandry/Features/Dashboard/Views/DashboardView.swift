//
//  DashboardView.swift
//  loandry
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()
    @Environment(AppRouter.self) var appRouter
    @Environment(NotificationManager.self) var notificationManager
    @AppStorage("notifications.prompted") private var didPromptForNotifications = false
    
    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            LoanListView()
                .navigationTitle("Loans")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            viewModel.showCreateSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
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
                .navigationDestination(for: Loan.self) { loan in
                    LoanDetailView(loan: loan)
                }
                .navigationDestination(for: DashboardViewModel.DeepLinkedLoan.self) { target in
                    if let loan = LoanManager.shared.loans.first(where: { $0.id == target.loanID }) {
                        LoanDetailView(loan: loan, initialSelectedPaymentID: target.paymentID)
                    } else {
                        ContentUnavailableView("Loan Not Found", systemImage: "exclamationmark.triangle")
                    }
                }
                .onChange(of: LoanManager.shared.loans.count) { _, _ in
                    viewModel.handleDeepLink(route: appRouter.pendingRoute)
                    if appRouter.pendingRoute != nil {
                         _ = appRouter.consumeRoute()
                    }
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
}
