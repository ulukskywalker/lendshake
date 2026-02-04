//
//  DashboardView.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct DashboardView: View {
    @Environment(LoanManager.self) var loanManager
    @State private var selectedStatus: LoanFilter = .active
    
    enum LoanFilter: String, CaseIterable, Identifiable {
        case active = "Active"
        case completed = "Closed"
        case draft = "Drafts"
        
        var id: String { self.rawValue }
    }
    
    var filteredLoans: [Loan] {
        let result = loanManager.loans.filter { loan in
            switch selectedStatus {
            case .draft:
                return loan.status == .draft
            case .active:
                return loan.status == .active || loan.status == .sent
            case .completed:
                return loan.status == .completed || loan.status == .cancelled || loan.status == .forgiven
            }
        }
        print("DEBUG: Filtered \(loanManager.loans.count) loans (Status: \(selectedStatus.rawValue)) -> \(result.count) returned")
        if loanManager.loans.count > 0 {
            print("Debug Loan Statuses: \(loanManager.loans.map { $0.status })")
        }
        return result
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.lsBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                LoanListView(loans: filteredLoans, selectedStatus: $selectedStatus)
                    
                    
                    
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
