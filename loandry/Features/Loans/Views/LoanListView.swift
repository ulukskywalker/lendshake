//
//  LoanListView.swift
//  loandry
//
//  Created by Assistant on 2/2/26.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

private enum CarouselMetrics {
    static let peekHeight: CGFloat = 88                    // Visible strip of each card behind the front
    static let cardCornerRadius: CGFloat = 14
    static let cardHorizontalPadding: CGFloat = 0
    
    // 3D perspective: looking down at the stack from above
    static let scaleStep: CGFloat = 0.02                   // Each card behind shrinks by this much
    static let maxTiltDegrees: Double = 1.5                // Subtle X rotation per card
    static let perspectiveValue: CGFloat = 0.3             // Perspective projection strength
    
    // Collapsed state (when a card is expanded)
    static let collapsedPeekHeight: CGFloat = 16           // Peek height when stacked at bottom
    static let bottomStackBaseVisible: CGFloat = 80        // How much of the bottom area is reserved for the stack
}

// MARK: - Main Carousel View

struct LoanListView: View {
    @Environment(LoanManager.self) var loanManager
    @Environment(AuthManager.self) var authManager
    @Binding var selectedLoan: Loan?
    
    // Delete alert state
    @State private var loanToDelete: Loan?
    @State private var showDeleteAlert: Bool = false
    @State private var deleteErrorMessage: String?
    
    // Is a card expanded?
    private var isExpanded: Bool { selectedLoan != nil }
    
    // Sorted loans: attention first, then active lending, active borrowing, drafts, history
    var sortedLoans: [Loan] {
        return loanManager.loans.sorted {
            $0.lastActivityDate > $1.lastActivityDate
        }
    }
    
    var body: some View {
        GeometryReader { geo in
            let safeHeight = geo.size.height
            let totalCards = sortedLoans.count
            // Push cards down slightly to give room for floating buttons
            let dynamicTopInset = safeHeight * 0.08
            let cardHeight = safeHeight - dynamicTopInset - (CGFloat(max(0, totalCards - 1)) * CarouselMetrics.peekHeight)
            
            ZStack(alignment: .top) {
                // Black background
                Color.black
                    .ignoresSafeArea()
                
                if loanManager.isLoading && loanManager.loans.isEmpty {
                    loadingState
                } else if loanManager.loans.isEmpty {
                    emptyState
                } else {
                    carouselStack(
                        cardHeight: max(200, cardHeight),
                        totalCards: totalCards,
                        screenHeight: safeHeight,
                        topInset: dynamicTopInset
                    )
                }
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
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
    
    // MARK: - Loading State
    
    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView()
                .tint(.white)
            Text("Loading loans...")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.3))
            Text("No loans yet")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.6))
            Text("Tap + to create your first loan")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Card Stack
    
    private func carouselStack(cardHeight: CGFloat, totalCards: Int, screenHeight: CGFloat, topInset: CGFloat) -> some View {
        let selectedIndex = sortedLoans.firstIndex(where: { $0.id == selectedLoan?.id })
        
        return ZStack(alignment: .top) {
            // ── Loan cards (rendered back to front) ──
            ForEach(Array(sortedLoans.enumerated().reversed()), id: \.element.id) { index, loan in
                let isLender = loanManager.isLender(of: loan)
                let isThisSelected = loan.id == selectedLoan?.id
                // When expanded, the selected card fills the screen but leaves a small gap before the bottom stack
                // All cards are kept uniformly tall to prevent ScrollView bounds resizing during collapse
                let effectiveHeight = screenHeight - CarouselMetrics.bottomStackBaseVisible - 10
                let themeColor = cardThemeColor(loan: loan, isLender: isLender)
                
                LoanCardContainer(
                    loan: loan,
                    isLender: isLender,
                    cardHeight: effectiveHeight,
                    isExpanded: isThisSelected && isExpanded,
                    themeColor: themeColor,
                    onCollapse: {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            selectedLoan = nil
                        }
                    },
                    onSelect: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                            selectedLoan = loan
                        }
                    }
                )
                .contextMenu {
                    if loan.status == .draft {
                        Button(role: .destructive) {
                            loanToDelete = loan
                            showDeleteAlert = true
                        } label: {
                            Label("Delete Draft", systemImage: "trash")
                        }
                    }
                }
                .padding(.horizontal, CarouselMetrics.cardHorizontalPadding)
                .modifier(CardStackModifier(
                    index: index,
                    selectedIndex: selectedIndex,
                    totalCards: totalCards,
                    screenHeight: screenHeight,
                    isExpanded: isExpanded,
                    topInset: topInset
                ))
                .zIndex(Double(totalCards - index))
                .onTapGesture {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        if isThisSelected {
                            // Tapping expanded card — do nothing, detail is interactive
                        } else if isExpanded {
                            // Tapping a different card while one is expanded → switch
                            selectedLoan = loan
                        } else {
                            // Normal tap → expand
                            selectedLoan = loan
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func cardThemeColor(loan: Loan, isLender: Bool) -> Color {
        if loan.status == .draft { return Color.gray }
        if [LoanStatus.completed, .forgiven, .cancelled].contains(loan.status) { return Color(uiColor: .systemGray3) }
        return isLender ? Color.blue : Color.orange
    }
}

// MARK: - Loan Card Container

/// A card that shows a peek header strip + LoanDetailView as the body.
/// The card IS the detail view — no separate overlay or navigation push.
private struct LoanCardContainer: View {
    let loan: Loan
    let isLender: Bool
    let cardHeight: CGFloat
    let isExpanded: Bool
    let themeColor: Color
    var onCollapse: () -> Void
    var onSelect: () -> Void
    
    @Environment(LoanManager.self) var loanManager
    @Environment(AuthManager.self) var authManager
    @Environment(\.colorScheme) var colorScheme
    @State private var fetchedLenderName: String?
    @State private var showInfoSheet: Bool = false
    @State private var showAgreementSheet: Bool = false
    @GestureState private var pullDragOffset: CGFloat = 0
    
    var counterpartyName: String {
        if isLender {
            return loan.borrower_name_snapshot ?? loan.borrower_name ?? loan.borrower_email ?? "Unknown"
        } else {
            return loan.lender_name_snapshot ?? fetchedLenderName ?? "Lender"
        }
    }
    
    

    var body: some View {
        VStack(spacing: 0) {
            // ── Top Highlight for Dark Mode Visibility ──
            if colorScheme == .dark {
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(height: 0.5)
            }

            // ── Peek header strip (always visible) ──
            headerStrip
            
            // ── LoanDetailView as the card body ──
            LoanDetailView(loan: loan)
                .allowsHitTesting(isExpanded)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .background(
            ZStack {
                (colorScheme == .dark ? Color(uiColor: .secondarySystemBackground) : Color(uiColor: .systemBackground))
                GrainOverlay()
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: CarouselMetrics.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CarouselMetrics.cardCornerRadius, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: -3)
        .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: -1)
        .offset(y: pullDragOffset)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: pullDragOffset)
        .fullScreenCover(isPresented: $showInfoSheet) {
            loanInfoView
        }
        .task(id: loan.lender_id) {
            if !isLender {
                if let name = await authManager.fetchProfileName(for: loan.lender_id) {
                    fetchedLenderName = name
                }
            }
        }
    }
    
    // MARK: - Header Strip
    
    private var headerStrip: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(counterpartyName)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                
                Spacer()
                
                Text(loan.principal_amount.formatted(.currency(code: "USD")))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isLender ? .green : .red)
                
                Image(systemName: "info.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(.blue)
                    .padding(8)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            if !isExpanded {
                                onSelect()
                                // Wait for the spring animation to almost finish before showing the sheet
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                    showInfoSheet = true
                                }
                            } else {
                                showInfoSheet = true
                            }
                        }
                    )
            }
            .padding(.horizontal, 20)
            .frame(height: CarouselMetrics.peekHeight)
            
            // Wider bottom rule
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.3))
                .frame(height: 1.5)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isExpanded {
                onCollapse()
            } else {
                onSelect()
            }
        }
        .gesture(
            DragGesture()
                .updating($pullDragOffset) { value, state, _ in
                    if isExpanded {
                        // Only allow dragging downwards
                        state = max(0, value.translation.height)
                    }
                }
                .onEnded { value in
                    if isExpanded {
                        // If pulled down far enough or fast enough, trigger collapse
                        if value.translation.height > 60 || value.predictedEndTranslation.height > 100 {
                            onCollapse()
                        }
                    }
                }
        )
    }
    
    // MARK: - Loan Info View (slides from right)
    
    private var loanInfoView: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack(spacing: 10) {
                Button {
                    showInfoSheet = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                        Text("Back")
                            .font(.system(size: 16))
                    }
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text("Loan Info")
                    .font(.system(size: 16, weight: .semibold))
                
                Spacer()
                
                // Invisible balance for centering
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                    Text("Back")
                        .font(.system(size: 16))
                }
                .opacity(0)
            }
            .padding(.horizontal, 20)
            .frame(height: CarouselMetrics.peekHeight)
            
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.3))
                .frame(height: 1.5)
            
            // Content
            List {
                Section {
                    LabeledContent("Role", value: isLender ? "Lender" : "Borrower")
                    LabeledContent("Status", value: loan.status.title)
                }
                
                Section("Parties") {
                    LabeledContent("Lender", value: isLender ? "You" : counterpartyName)
                    LabeledContent("Borrower", value: isLender ? counterpartyName : "You")
                }
                
                Section("Financial Terms") {
                    LabeledContent("Principal", value: loan.principal_amount.formatted(.currency(code: "USD")))
                    LabeledContent("Interest Rate", value: "\(loan.interest_rate.formatted())%")
                    LabeledContent("Repayment", value: loan.repayment_schedule.capitalized)
                    LabeledContent("Late Fee", value: loan.late_fee_policy)
                }
                
                Section("Dates") {
                    if let created = loan.created_at {
                        LabeledContent("Created", value: created.formatted(date: .abbreviated, time: .omitted))
                    }
                    LabeledContent("Maturity", value: loan.maturity_date.formatted(date: .abbreviated, time: .omitted))
                }
                
                if let remaining = loan.remaining_balance {
                    Section("Balance") {
                        LabeledContent("Remaining", value: remaining.formatted(.currency(code: "USD")))
                        let paid = loan.principal_amount - remaining
                        LabeledContent("Paid", value: paid.formatted(.currency(code: "USD")))
                    }
                }
                
                if loan.status == .cancelled,
                   let reason = loan.agreement_rejection_reason?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !reason.isEmpty {
                    Section("Rejection") {
                        Text(reason)
                    }
                }
                
                Section("Documents") {
                    Button {
                        showAgreementSheet = true
                    } label: {
                        HStack {
                            Text("View Contract")
                            Spacer()
                            Image(systemName: "doc.text")
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .listStyle(.insetGrouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(isPresented: $showAgreementSheet) {
            AgreementReviewSheetView(isPresented: $showAgreementSheet, loan: loan, isLender: isLender)
        }
    }
}

// MARK: - Card Stack Position Modifier

/// Handles the position, scale, and 3D rotation of each card
/// in both the normal stacked state and the expanded state.
private struct CardStackModifier: ViewModifier {
    let index: Int
    let selectedIndex: Int?        // nil = no card selected
    let totalCards: Int
    let screenHeight: CGFloat
    let isExpanded: Bool
    let topInset: CGFloat
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(x: max(0.85, scale), y: 1.0, anchor: .top)
            .rotation3DEffect(
                .degrees(tilt),
                axis: (x: 1, y: 0, z: 0),
                anchor: .top,
                perspective: CarouselMetrics.perspectiveValue
            )
            .offset(y: yOffset)
    }
    
    // MARK: - Computed Positions
    
    private var yOffset: CGFloat {
        if isExpanded, let sel = selectedIndex {
            if index == sel {
                // Selected card goes to the very top to cover buttons
                return 0
            } else {
                // Other cards slide down to form a stack at the bottom.
                // We order them by index so they naturally layer.
                // The base of the stack starts near the bottom of the screen.
                // We add a small extra offset here to make the gap look intentional.
                let stackBase = screenHeight - CarouselMetrics.bottomStackBaseVisible + 5
                
                // Adjust index so the stack at the bottom looks ordered regardless of sel.
                let visualBottomIndex = index < sel ? index : index - 1
                return stackBase + CGFloat(visualBottomIndex) * CarouselMetrics.collapsedPeekHeight
            }
        } else {
            // Normal stacked position
            let invertedIndex = CGFloat(totalCards - 1 - index)
            return topInset + invertedIndex * CarouselMetrics.peekHeight
        }
    }
    
    private var scale: CGFloat {
        if isExpanded, let sel = selectedIndex {
            if index == sel {
                return 1.0
            } else {
                // Collapsed cards at bottom: no perspective shrink
                return 1.0
            }
        } else {
            return 1.0 - (CarouselMetrics.scaleStep * CGFloat(index))
        }
    }
    
    private var tilt: Double {
        if isExpanded {
            return 0 // No tilt when expanded/collapsed
        } else {
            return -CarouselMetrics.maxTiltDegrees * Double(index)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LoanListView(selectedLoan: .constant(nil))
    }
    .environment(LoanManager.shared)
    .environment(AuthManager.shared)
    .environment(AppRouter())
}

// MARK: - Local Helpers

extension Loan {
    var lastActivityDate: Date {
        let dates: [Date?] = [created_at, lender_signed_at, borrower_signed_at]
        let validDates = dates.compactMap { $0 }
        return validDates.max() ?? .distantPast
    }
}

// MARK: - Paper Grain Overlay

struct GrainOverlay: View {
    @State private var noiseImage: Image?
    
    var body: some View {
        Group {
            if let noiseImage = noiseImage {
                noiseImage
                    .resizable(resizingMode: .tile)
                    .saturation(0)
                    .opacity(0.04)
            } else {
                Color.clear
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            DispatchQueue.global(qos: .userInteractive).async {
                let context = CIContext()
                let noiseFilter = CIFilter.randomGenerator()
                if let output = noiseFilter.outputImage,
                   let cgimg = context.createCGImage(output, from: CGRect(x: 0, y: 0, width: 200, height: 200)) {
                    let image = Image(cgimg, scale: 1, label: Text("Noise"))
                    DispatchQueue.main.async {
                        self.noiseImage = image
                    }
                }
            }
        }
    }
}
