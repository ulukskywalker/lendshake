//
//  DashboardView.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct DashboardView: View {
    @Environment(LoanManager.self) var loanManager
    @State private var showCreateSheet: Bool = false
    @State private var path = NavigationPath()
    
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
            .sheet(isPresented: $showCreateSheet) {
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
}
    
#Preview {
    DashboardView()
        .environment(LoanManager())
}
