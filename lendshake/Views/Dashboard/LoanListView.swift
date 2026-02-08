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
    
    // Filtered Lists
    var visibleLoans: [Loan] {
        loanManager.loans
    }

    var lendingLoans: [Loan] {
        visibleLoans.filter {
            loanManager.isLender(of: $0) &&
            ($0.status == .active || $0.status == .sent || $0.status == .approved || $0.status == .funding_sent)
        }
    }
    
    var borrowingLoans: [Loan] {
        visibleLoans.filter {
            !loanManager.isLender(of: $0) &&
            ($0.status == .active || $0.status == .sent || $0.status == .approved || $0.status == .funding_sent)
        }
    }
    
    var draftLoans: [Loan] {
        visibleLoans.filter { $0.status == .draft }
    }
    
    var historyLoans: [Loan] {
        visibleLoans.filter { $0.status == .completed || $0.status == .forgiven || $0.status == .cancelled }
    }
    
    var body: some View {
        List {
            if loanManager.isLoading && loanManager.loans.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading loans...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .padding(.top, 40)
            } else if loanManager.loans.isEmpty {
                ContentUnavailableView("No Shakes Yet", systemImage: "doc.text.magnifyingglass")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.top, 40)
            } else {
                
                // 1. LENDING SECTION (Green)
                if !lendingLoans.isEmpty {
                    Section {
                        ForEach(lendingLoans) { loan in
                            loanRow(for: loan)
                        }
                    } header: {
                        HStack {
                            Image(systemName: "arrow.up.right")
                            Text("Owes You (Assets)")
                        }
                        .foregroundStyle(Color.lsPrimary)
                        .font(.headline)
                        .textCase(nil)
                        .padding(.vertical, 8)
                    }
                }
                
                // 2. BORROWING SECTION (Orange)
                if !borrowingLoans.isEmpty {
                    Section {
                        ForEach(borrowingLoans) { loan in
                            loanRow(for: loan)
                        }
                    } header: {
                        HStack {
                            Image(systemName: "arrow.down.left")
                            Text("You Owe (Liabilities)")
                        }
                        .foregroundStyle(Color.orange)
                        .font(.headline)
                        .textCase(nil)
                        .padding(.vertical, 8)
                    }
                }
                
                // 3. DRAFTS SECTION
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
                
                // 4. HISTORY SECTION
                if !historyLoans.isEmpty {
                    Section {
                        DisclosureGroup("Show History (\(historyLoans.count))") {
                            ForEach(historyLoans) { loan in
                                loanRow(for: loan)
                            }
                        }
                        .tint(.secondary)
                    } header: {
                        Text("Completed")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.lsBackground)
        .overlay(alignment: .top) {
            if loanManager.isLoading && !loanManager.loans.isEmpty {
                ProgressView()
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
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
    @Environment(AuthManager.self) var authManager
    @State private var fetchedLenderName: String?
    
    // Theme Colors based on Role
    var themeColor: Color {
        isLender ? Color.lsPrimary : Color.orange
    }
    
    var counterpartyName: String {
        if isLender {
            return loan.borrower_name ?? "Unknown Borrower"
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
                    .font(.body) // Standard list body font
                    .fontWeight(.medium)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(loan.status.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill((loan.status == .active ? themeColor : Color.secondary).opacity(0.12))
                        )
                        .foregroundStyle(loan.status == .active ? themeColor : .secondary)
                    
                    if loan.status == .draft {
                        Text("• " + (loan.created_at?.formatted(date: .abbreviated, time: .omitted) ?? ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // 3. Trailing Amount (Wallet Style)
            VStack(alignment: .trailing, spacing: 2) {
                // Prefix: + for Lender, - for Borrower
                let amountText = loan.principal_amount.formatted(.currency(code: "USD"))
                let prefix = isLender ? "+" : "-"
                
                Text("\(prefix)\(amountText)")
                    .font(.callout) // Standard numeric font size
                    .fontWeight(.medium) // Not too bold, just standard
                    .foregroundStyle(loan.status == .completed || loan.status == .forgiven ? .gray : themeColor)
                
                if loan.status == .active {
                     Text("Balance")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4) // Reduced padding for standard list feel
        .contentShape(Rectangle())
        .task {
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
        .environment(LoanManager())
}
