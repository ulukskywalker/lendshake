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
                return loan.status == .completed || loan.status == .cancelled
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
                    VStack(spacing: 0) {
                        // Filter Chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(LoanFilter.allCases) { status in
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            selectedStatus = status
                                        }
                                    } label: {
                                        Text(status.rawValue)
                                            .font(.subheadline)
                                            .bold()
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(selectedStatus == status ? Color.lsPrimary : Color.lsSecondary.opacity(0.1))
                                            .foregroundStyle(selectedStatus == status ? .white : .primary)
                                            .clipShape(Capsule())
                                            .overlay(
                                                Capsule()
                                                    .strokeBorder(selectedStatus == status ? Color.clear : Color.gray.opacity(0.2), lineWidth: 1)
                                            )
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        .background(Color.lsBackground)
                        
                        Group {
                            if loanManager.isLoading {
                                ProgressView("Loading...")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if filteredLoans.isEmpty {
                                EmptyStateView()
                            } else {
                                LoanListView(loans: filteredLoans)
                            }
                        }
                    }
                    
                    
                    
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
