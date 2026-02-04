//
//  DashboardView.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct DashboardView: View {
    @Environment(LoanManager.self) var loanManager
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.lsBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    LoanListView()
                }
                .toolbar {
                    
                    
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink(destination: LoanConstructionView()) {
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
        }
    }
}
    
#Preview {
    DashboardView()
        .environment(LoanManager())
}
