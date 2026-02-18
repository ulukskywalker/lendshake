import SwiftUI

struct LoanConstructionDatesStepView: View {
    @Binding var repaymentSchedule: RepaymentSchedule
    @Binding var maturityDate: Date
    @Binding var firstPaymentDate: Date
    @Binding var showDatePickerPopover: Bool
    
    @State private var showFirstPaymentPicker: Bool = false
    
    let onScheduleChange: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("Important Dates")
                        .font(.title2)
                        .bold()
                    Text("Set the schedule for repayment.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top)
                
                // 1. Frequency
                termSection(
                    icon: "repeat",
                    title: "Repayment Frequency",
                    subtitle: "How often will they pay you back?"
                ) {
                    Picker("Frequency", selection: $repaymentSchedule) {
                        ForEach(RepaymentSchedule.allCases) { schedule in
                            Text(schedule.rawValue).tag(schedule)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: repaymentSchedule) { _, _ in
                        onScheduleChange()
                    }
                }
                
                // 2. First Payment Date
                if repaymentSchedule != .lumpSum {
                    termSection(
                        icon: "calendar.badge.plus",
                        title: "First Payment Date",
                        subtitle: "When is the first installment due?"
                    ) {
                        Button {
                            showFirstPaymentPicker = true
                        } label: {
                            HStack {
                                Text(firstPaymentDate.formatted(date: .long, time: .omitted))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(12)
                        }
                        .popover(isPresented: $showFirstPaymentPicker) {
                            DatePicker("First Payment", selection: $firstPaymentDate, in: Date()..., displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .onChange(of: firstPaymentDate) { _, _ in
                                    showFirstPaymentPicker = false
                                }
                                .padding()
                                .frame(minWidth: 320)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // 3. Final Due Date
                termSection(
                    icon: "calendar",
                    title: "Final Due Date",
                    subtitle: "When should the total be paid off?"
                ) {
                    Button {
                        showDatePickerPopover = true
                    } label: {
                        HStack {
                            Text(maturityDate.formatted(date: .long, time: .omitted))
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(12)
                    }
                    .popover(isPresented: $showDatePickerPopover) {
                        DatePicker("Final Due Date", selection: $maturityDate, in: Date()..., displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .onChange(of: maturityDate) { _, _ in
                                showDatePickerPopover = false
                            }
                            .padding()
                            .frame(minWidth: 320)
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .background(Color.appBackground)
    }
    
    @ViewBuilder
    private func termSection<Content: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
                    .frame(width: 24, height: 24)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            
            content()
                .padding()
                .background(Color.cardBackground)
                .cornerRadius(16)
                .lsCardContainer()
        }
        .padding(.horizontal)
    }
    
}
