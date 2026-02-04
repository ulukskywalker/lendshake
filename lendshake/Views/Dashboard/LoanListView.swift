//
//  LoanListView.swift
//  lendshake
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI

struct LoanListView: View {
    let loans: [Loan]
    @Binding var selectedStatus: DashboardView.LoanFilter
    @Environment(LoanManager.self) var loanManager
    
    // For alert handling
    @State private var loanToDelete: Loan?
    @State private var showDeleteAlert: Bool = false
    
    var body: some View {
        List {
            Section(header: headerView) {
                if loans.isEmpty {
                    ContentUnavailableView("No \(selectedStatus.rawValue) Shakes", systemImage: "doc.text.magnifyingglass")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .padding(.top, 40)
                } else {
                    ForEach(loans) { loan in
                        ZStack {
                            // Navigation Link Hack to remove default arrow
                            NavigationLink(destination: LoanDetailView(loan: loan)) {
                                EmptyView()
                            }
                            .opacity(0)
                            
                            LoanCardView(loan: loan, isLender: loanManager.isLender(of: loan))
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
            }
        }
        .listStyle(.plain)
        .background(Color.lsBackground)
        .scrollContentBackground(.hidden) // Important for List background
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
    
    var headerView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(DashboardView.LoanFilter.allCases) { status in
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
                            .background(selectedStatus == status ? Color.lsPrimary : Color.white)
                            .foregroundStyle(selectedStatus == status ? .white : .primary)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                            .overlay(
                                Capsule()
                                    .strokeBorder(selectedStatus == status ? Color.clear : Color.gray.opacity(0.1), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal)
        }
        .background(Color.lsBackground.opacity(0.95))
        .listRowInsets(EdgeInsets()) // Remove padding for header
    }
}

struct LoanCardView: View {
    let loan: Loan
    let isLender: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isLender ? "LENDING TO" : "BORROWING FROM")
                        .font(.caption2)
                        .fontWeight(.heavy)
                        .foregroundStyle(Color.lsTextSecondary)
                        .tracking(0.5)
                    
                    Text(loan.borrower_name ?? "Unknown")
                        .font(.headline)
                        .foregroundStyle(Color.lsTextPrimary)
                }
                
                Spacer()
                
                LoanStatusBadge(status: loan.status)
            }
            
            Divider()
                .opacity(0.5)
            
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading) {
                    Text("Due Date")
                        .font(.caption)
                        .foregroundStyle(Color.lsTextSecondary)
                    Text(loan.maturity_date.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.lsTextPrimary)
                }
                
                Spacer()
                
                Text(loan.principal_amount, format: .currency(code: "USD"))
                    .font(.title3)
                    .bold()
                    .foregroundStyle(Color.lsPrimary)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }
}

#Preview {
       LoanListView(loans: [], selectedStatus: Binding.constant(DashboardView.LoanFilter.active))
           .environment(LoanManager())
   }
