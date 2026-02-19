import SwiftUI

struct LoanConstructionDatesStepView: View {
    @Binding var repaymentSchedule: RepaymentSchedule
    @Binding var maturityDate: Date
    @Binding var firstPaymentDate: Date
    @Binding var showDatePickerPopover: Bool
    
    // We can ignore showDatePickerPopover if we use inline/compact date pickers in a Form
    
    let onScheduleChange: () -> Void
    
    var body: some View {
        Form {
            Section {
                Picker("Repayment Frequency", selection: $repaymentSchedule) {
                    ForEach(RepaymentSchedule.allCases) { schedule in
                        Text(schedule.rawValue).tag(schedule)
                    }
                }
                .onChange(of: repaymentSchedule) { _, _ in
                    onScheduleChange()
                }
            } header: {
                Text("Schedule")
            } footer: {
                Text("How often will the borrower make payments?")
            }
            
            Section {
                if repaymentSchedule != .lumpSum {
                    DatePicker("First Payment", selection: $firstPaymentDate, in: Date()..., displayedComponents: .date)
                }
                
                DatePicker("Final Due Date", selection: $maturityDate, in: Date()..., displayedComponents: .date)
            } header: {
                Text("Key Dates")
            } footer: {
               if repaymentSchedule != .lumpSum {
                   Text("The first payment is due on \(firstPaymentDate.formatted(date: .abbreviated, time: .omitted)). The loan must be fully repaid by the final due date.")
               } else {
                   Text("The full amount is due on \(maturityDate.formatted(date: .abbreviated, time: .omitted)).")
               }
            }
        }
    }
}
