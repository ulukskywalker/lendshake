//
//  LoanListView.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct LoanListView: View {
    @Environment(LoanManager.self) var loanManager
    
    // For alert handling
    @State private var loanToDelete: Loan?
    @State private var showDeleteAlert: Bool = false
    
    var activeLoans: [Loan] {
        loanManager.loans.filter { $0.status == .active || $0.status == .sent }
    }
    
    var draftLoans: [Loan] {
        loanManager.loans.filter { $0.status == .draft }
    }
    
    var historyLoans: [Loan] {
        loanManager.loans.filter { $0.status == .completed || $0.status == .forgiven || $0.status == .cancelled }
    }
    
    var body: some View {
        List {
            if loanManager.loans.isEmpty {
                ContentUnavailableView("No Shakes Yet", systemImage: "doc.text.magnifyingglass")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.top, 40)
            } else {
                // ACTIVE SECTION
                if !activeLoans.isEmpty {
                    Section {
                        ForEach(activeLoans) { loan in
                            loanRow(for: loan)
                        }
                    } header: {
                        Text("Active Loans")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .textCase(nil) // Remove default UPPERCASE
                            .padding(.vertical, 8)
                    }
                }
                
                // DRAFTS SECTION
                if !draftLoans.isEmpty {
                    Section {
                        ForEach(draftLoans) { loan in
                            loanRow(for: loan)
                        }
                    } header: {
                        Text("Drafts")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .textCase(nil)
                            .padding(.vertical, 8)
                    }
                }
                
                // HISTORY SECTION
                if !historyLoans.isEmpty {
                    Section {
                        ForEach(historyLoans) { loan in
                            loanRow(for: loan)
                        }
                    } header: {
                        Text("History")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
        .listStyle(.insetGrouped) // The "Apple Standard" for grouped content
        .scrollContentBackground(.hidden)
        .background(Color.lsBackground)
        .alert("Delete Draft Loan?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let loan = loanToDelete {
                    Task {
                        try? await loanManager.deleteLoan(loan)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this draft? This action cannot be undone.")
        }
    }
    
    @ViewBuilder
    func loanRow(for loan: Loan) -> some View {
        ZStack {
            NavigationLink(destination: LoanDetailView(loan: loan)) {
                EmptyView()
            }
            .opacity(0)
            
            LoanCardView(loan: loan, isLender: loanManager.isLender(of: loan))
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if loan.status == .draft {
                Button(role: .destructive) {
                    loanToDelete = loan
                    showDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

struct LoanCardView: View {
    let loan: Loan
    let isLender: Bool
    
    var statusColor: Color {
        switch loan.status {
        case .draft: return .gray
        case .active: return .green
        case .sent: return .blue
        case .completed: return .green
        case .forgiven: return .gray
        default: return .gray
        }
    }
    
    var counterpartyName: String {
        if isLender {
            return loan.borrower_name ?? "Unknown Borrower"
        } else {
            return "Lender" // Placeholder until we have lender_name
        }
    }
    
    var roleText: String {
        isLender ? "Lending" : "Borrowing"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top Row: Name and Amount
            HStack(alignment: .firstTextBaseline) {
                Text(counterpartyName)
                    .font(.headline)
                    .foregroundStyle(Color.lsTextPrimary)
                
                Spacer()
                
                Text(loan.principal_amount, format: .currency(code: "USD"))
                    .font(.system(.title3, design: .rounded))
                    .bold()
                    .foregroundStyle(loan.status == .completed || loan.status == .forgiven ? .gray : Color.lsTextPrimary)
            }
            
            // Bottom Row: Status Pill, Role, Detail
            HStack(alignment: .center) {
                // Status Pill
                Text(loan.status.title)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15))
                    .clipShape(Capsule())
                
                // Role Indicator
                Text("•  \(roleText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Contextual Detail
                if loan.status == .active {
                   Text("Current Balance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if loan.status == .draft {
                    Text(loan.created_at?.formatted(date: .abbreviated, time: .omitted) ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4) // Give the card some breathing room inside the list row
        .contentShape(Rectangle())
    }
}

#Preview {
    LoanListView()
        .environment(LoanManager())
}
