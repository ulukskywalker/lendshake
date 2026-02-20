//
//  DashboardViewModel.swift
//  loandry
//
//  Created by Assistant on 2/18/26.
//

import SwiftUI
import Observation

@MainActor
@Observable
class DashboardViewModel {
    var showCreateSheet: Bool = false
    var selectedLoan: Loan? = nil
    
    init() {}
    
    var errorMessage: String?
    
    func onAppear() async {
        if LoanManager.shared.loans.isEmpty {
            await fetchLoans()
        }
    }
    
    func onRefresh() async {
        await fetchLoans()
    }
    
    private func fetchLoans() async {
        errorMessage = nil
        do {
            try await LoanManager.shared.fetchLoans()
        } catch {
            print("Dashboard Error: \(error)")
            errorMessage = "Failed to load loans: \(error.localizedDescription)"
        }
    }
    
    func handleDeepLink(route: AppRouter.Route?) {
        guard let route = route else { return }
        
        switch route {
        case .loan(let loanID, _):
            if let loan = LoanManager.shared.loans.first(where: { $0.id == loanID }) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    selectedLoan = loan
                }
            }
        }
    }
    
    func onLoanCreated(newLoan: Loan) {
        showCreateSheet = false
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                selectedLoan = newLoan
            }
        }
    }
    
    func collapseLoan() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            selectedLoan = nil
        }
    }
    
    /// Auto-close expansion if the selected loan no longer exists (e.g. deleted)
    func checkSelectedLoanExists() {
        guard let selected = selectedLoan else { return }
        if !LoanManager.shared.loans.contains(where: { $0.id == selected.id }) {
            collapseLoan()
        }
    }
}
