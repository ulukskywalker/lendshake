//
//  DashboardView.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct DashboardView: View {
    @Environment(LoanManager.self) var loanManager
    @Environment(AppRouter.self) var appRouter
    @State private var showCreateSheet: Bool = false
    @State private var path = NavigationPath()
    @State private var deepLinkToken = UUID()

    private struct DeepLinkedLoan: Hashable {
        let loanID: UUID
        let paymentID: UUID?
        let token: UUID
    }
    
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.lsBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    LoanListView()
                }
                .toolbar {
                    
                    
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showCreateSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline)
                                .foregroundStyle(Color.lsPrimary)
                        }
                    }
                }
                .navigationTitle("Lendshake")
                .toolbarBackground(.visible, for: .navigationBar)
                .task {
                    if loanManager.loans.isEmpty {
                        do {
                            try await loanManager.fetchLoans()
                        } catch {
                            print("Dashboard Task Error: \(error)")
                        }
                    }
                }
                .refreshable {
                    do {
                        try await loanManager.fetchLoans()
                    } catch {
                        print("Dashboard Refresh Error: \(error)")
                    }
                }
            }
            .navigationDestination(for: Loan.self) { loan in
                LoanDetailView(loan: loan)
            }
            .navigationDestination(for: DeepLinkedLoan.self) { target in
                if let loan = loanManager.loans.first(where: { $0.id == target.loanID }) {
                    LoanDetailView(loan: loan, initialSelectedPaymentID: target.paymentID)
                } else {
                    ContentUnavailableView("Loan Not Found", systemImage: "exclamationmark.triangle")
                }
            }
            .onChange(of: loanManager.loans.count) { _, _ in
                consumePendingDeepLinkIfPossible()
            }
            .onChange(of: appRouter.pendingRoute != nil) { _, _ in
                consumePendingDeepLinkIfPossible()
            }
            .fullScreenCover(isPresented: $showCreateSheet) {
                NavigationStack {
                    LoanConstructionView(onLoanCreated: { newLoan in
                        showCreateSheet = false
                        // Small delay to allow sheet to dismiss before pushing
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            path.append(newLoan)
                        }
                    })
                }
            }
        }
    }

    private func consumePendingDeepLinkIfPossible() {
        guard let route = appRouter.pendingRoute else { return }
        switch route {
        case .loan(let loanID, let paymentID):
            guard loanManager.loans.contains(where: { $0.id == loanID }) else { return }
            deepLinkToken = UUID()
            path.append(DeepLinkedLoan(loanID: loanID, paymentID: paymentID, token: deepLinkToken))
            _ = appRouter.consumeRoute()
        }
    }
}
    
#Preview {
    DashboardView()
        .environment(LoanManager())
}
