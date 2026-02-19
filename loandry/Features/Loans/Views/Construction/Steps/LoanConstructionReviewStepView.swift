import SwiftUI

struct LoanConstructionReviewStepView: View {
    let principalAmount: String
    let interestRate: String
    let repaymentSchedule: RepaymentSchedule
    let maturityDate: Date
    let firstPaymentDate: Date
    let lateFeePolicy: String
    let lenderName: String
    let borrowerName: String
    let borrowerEmail: String

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Does this look right?")
                    .font(.title2)
                    .bold()
                    .padding(.top)

                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        Text("PROMISSORY NOTE")
                            .font(.caption)
                            .bold()
                            .tracking(3)
                            .foregroundStyle(.secondary)
                            .padding(.top)

                        Text("\(Double(principalAmount)?.formatted(.currency(code: "USD")) ?? "$0")")
                            .font(.system(size: 48, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.blue)
                            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)

                        if (Double(interestRate) ?? 0) == 0 {
                            Text("FAMILY RATE (0%)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.1))
                                .foregroundStyle(.green)
                                .cornerRadius(20)
                        } else {
                            Text("\(interestRate)% ANNUAL INTEREST")
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.orange.opacity(0.1))
                                .foregroundStyle(.orange)
                                .cornerRadius(20)
                        }
                    }
                    .padding(.vertical, 30)
                    .frame(maxWidth: .infinity)
                    .background(Color.cardBackground)

                    Divider()

                    VStack(spacing: 20) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("REPAYMENT")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                Text(repaymentSchedule.rawValue)
                                    .font(.body)
                                    .fontWeight(.semibold)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text("FIRST PAYMENT")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                Text(firstPaymentDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.body)
                                    .fontWeight(.semibold)
                            }
                        }

                        Divider().opacity(0.5)

                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("MATURITY DATE")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                Text(maturityDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.body)
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }

                        Divider().opacity(0.5)

                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("LATE FEE POLICY")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                if let fee = Double(lateFeePolicy), fee > 0 {
                                    Text("\(fee.formatted(.currency(code: "USD"))) after grace period")
                                        .font(.body)
                                        .fontWeight(.semibold)
                                } else {
                                    Text("No Late Fee")
                                        .font(.body)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }

                        Divider().opacity(0.5)

                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("LENDER")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                Text(lenderName)
                                    .font(.body)
                                    .fontWeight(.bold)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text("BORROWER")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                if !borrowerName.isEmpty {
                                    Text(borrowerName)
                                        .font(.body)
                                        .fontWeight(.bold)
                                }
                                Text(borrowerEmail)
                                    .font(.body)
                                    .foregroundStyle(borrowerName.isEmpty ? .primary : .secondary)
                            }
                        }
                    }
                    .padding(24)
                    .background(Color.gray.opacity(0.04))
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.08), radius: 15, x: 0, y: 5)
                .padding(.horizontal, 24)
                
                LoanConstructionTipCardView(
                    title: "Final Step",
                    message: "Clicking 'Create & Send' will sign the agreement as the lender and send it to the borrower to sign."
                )
                .padding(.horizontal, 24)
                .padding(.top)

                Spacer()
            }
        }
    }
}
