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
    var navigationPath = NavigationPath()
    
    // Dependencies
    // Note: We access LoanManager via the singleton in the VM for actions,
    // but the View might still observe it directly or via VM.
    // For MVVM purity, the VM should expose what the View needs.
    // However, since LoanManager is already an @Observable singleton, existing views rely on it.
    // We will keep using LoanManager.shared for actions.
    
    // Deep linking state
    struct DeepLinkedLoan: Hashable {
        let loanID: UUID
        let paymentID: UUID?
        // Token to force uniqueness if needed, though loanID+paymentID is usually unique enough for a route.
        // Keeping it to match previous logic if necessary, or simplification.
        let token = UUID()
    }
    
    init() {
        // Initialization if needed
    }
    
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
        case .loan(let loanID, let paymentID):
            // Only navigate if we have the loan loaded
            if LoanManager.shared.loans.contains(where: { $0.id == loanID }) {
                let deepLink = DeepLinkedLoan(loanID: loanID, paymentID: paymentID)
                navigationPath.append(deepLink)
            }
        }
    }
    
    func onLoanCreated(newLoan: Loan) {
        showCreateSheet = false
        // Small delay to allow sheet to dismiss interaction to finish before pushing
        // This is a UI-specific delay, but acceptable to orchestrate here or in View.
        // Using Task to handle the async delay on MainActor
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            navigationPath.append(newLoan)
        }
    }
}
