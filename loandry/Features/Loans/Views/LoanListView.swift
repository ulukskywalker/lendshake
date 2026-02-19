//
//  LoanListView.swift
//  loandry
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct LoanListView: View {
    @Environment(LoanManager.self) var loanManager
    
    // For alert handling
    @State private var loanToDelete: Loan?
    @State private var showDeleteAlert: Bool = false
    @State private var deleteErrorMessage: String?
    
    // Filtered Lists
    var visibleLoans: [Loan] {
        loanManager.loans
    }
    
    var attentionLoans: [Loan] {
        visibleLoans.filter { loanManager.requiredActionLabel(for: $0) != nil }
    }
    
    var lendingLoans: [Loan] {
        visibleLoans.filter {
            !isAttentionLoan($0) &&
            loanManager.isLender(of: $0) &&
            ($0.status == .active || $0.status == .sent || $0.status == .approved || $0.status == .funding_sent)
        }
    }
    
    var borrowingLoans: [Loan] {
        visibleLoans.filter {
            !isAttentionLoan($0) &&
            !loanManager.isLender(of: $0) &&
            ($0.status == .active || $0.status == .sent || $0.status == .approved || $0.status == .funding_sent)
        }
    }
    
    var draftLoans: [Loan] {
        visibleLoans.filter { !isAttentionLoan($0) && $0.status == .draft }
    }
    
    var historyLoans: [Loan] {
        visibleLoans.filter {
            !isAttentionLoan($0) &&
            ($0.status == .completed || $0.status == .forgiven || $0.status == .cancelled)
        }
    }
    
    func isAttentionLoan(_ loan: Loan) -> Bool {
        guard let loanId = loan.id else { return false }
        return attentionLoans.contains(where: { $0.id == loanId })
    }
    
    var body: some View {
        List {
            if loanManager.isLoading && loanManager.loans.isEmpty {
                ProgressView("Loading loans...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else if loanManager.loans.isEmpty {
                ContentUnavailableView("No Shakes Yet", systemImage: "doc.text.magnifyingglass")
                    .listRowBackground(Color.clear)
            } else {
                if !attentionLoans.isEmpty {
                    Section {
                        ForEach(attentionLoans) { loan in
                            LoanRow(loan: loan)
                        }
                    } header: {
                        Text("Needs Attention")
                    }
                }
                
                if !lendingLoans.isEmpty {
                    Section {
                        ForEach(lendingLoans) { loan in
                            LoanRow(loan: loan)
                        }
                    } header: {
                        Text("Assets")
                    }
                }
                
                if !borrowingLoans.isEmpty {
                    Section {
                        ForEach(borrowingLoans) { loan in
                            LoanRow(loan: loan)
                        }
                    } header: {
                        Text("Liabilities")
                    }
                }
                
                if !draftLoans.isEmpty {
                    Section {
                        ForEach(draftLoans) { loan in
                            LoanRow(loan: loan)
                        }
                    } header: {
                        Text("Drafts")
                    }
                }
                
                if !historyLoans.isEmpty {
                    Section {
                        ForEach(historyLoans) { loan in
                            LoanRow(loan: loan)
                        }
                    } header: {
                        Text("History")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .alert("Delete Draft Loan?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let loan = loanToDelete {
                    Task {
                        do {
                            try await loanManager.deleteLoan(loan)
                        } catch {
                            deleteErrorMessage = "Failed to delete draft: \(error.localizedDescription)"
                        }
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this draft? This action cannot be undone.")
        }
        .alert("Delete Failed", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                deleteErrorMessage = nil
            }
        } message: {
            Text(deleteErrorMessage ?? "Unknown error")
        }
    }
    
    @ViewBuilder
    func LoanRow(loan: Loan) -> some View {
        NavigationLink(value: loan) {
            LoanCardView(loan: loan, isLender: loanManager.isLender(of: loan))
        }
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
    @Environment(AuthManager.self) var authManager
    @Environment(LoanManager.self) var loanManager
    @State private var fetchedLenderName: String?
    
    // Theme Colors based on Role
    var themeColor: Color {
        isLender ? Color.blue : Color.orange
    }
    
    var counterpartyName: String {
        if isLender {
            return loan.borrower_name_snapshot ?? loan.borrower_name ?? loan.borrower_email ?? "Unknown Borrower"
        } else {
            return fetchedLenderName ?? "Lender"
        }
    }
    
    var initials: String {
        let components = counterpartyName.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        if let first = components.first, let last = components.last, components.count > 1 {
            return "\(first.prefix(1))\(last.prefix(1))".uppercased()
        } else if let first = components.first {
            return "\(first.prefix(1))".uppercased()
        }
        return "?"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 1. Leading Role Icon (Initials - Contacts Style)
            ZStack {
                Circle()
                    .fill(Color(uiColor: .systemGray5))
                    .frame(width: 40, height: 40)
                
                Text(initials)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.gray)
            }
            
            // 2. Center Info
            VStack(alignment: .leading, spacing: 2) {
                Text(counterpartyName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                
                if let attentionLabel = loanManager.requiredActionLabel(for: loan) {
                    Text(attentionLabel)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text(loan.status.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // 3. Trailing Amount (Wallet Style)
            VStack(alignment: .trailing, spacing: 2) {
                let amountText = loan.principal_amount.formatted(.currency(code: "USD"))
                let prefix = isLender ? "+" : "-"
                
                Text("\(prefix)\(amountText)")
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(loan.status == .completed || loan.status == .forgiven ? .gray : themeColor)
                
                if loan.status == .draft {
                     Text(loan.created_at?.formatted(date: .abbreviated, time: .omitted) ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .task(id: loan.lender_id) {
            if !isLender {
                if let name = await authManager.fetchProfileName(for: loan.lender_id) {
                    fetchedLenderName = name
                }
            }
        }
    }
}

#Preview {
    LoanListView()
        .environment(LoanManager.shared)
        .environment(AuthManager.shared)
        .environment(AppRouter())
}
