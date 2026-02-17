import SwiftUI

struct LoanConstructionTipCardView: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.caption)
                .foregroundStyle(Color.blue)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
