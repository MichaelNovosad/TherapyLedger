import SwiftUI

struct PaymentRow: View {
    let payment: Payment
    /// Converted amount in `displayCurrency` minor units, when converting.
    var convertedMinor: Int?
    var displayCurrency = "UAH"

    var body: some View {
        HStack {
            Image(systemName: payment.source == .monobank ? "bolt.circle.fill" : "hand.point.right.fill")
                .foregroundStyle(payment.source == .monobank ? .yellow : .secondary)
                .accessibilityLabel(payment.source.label)
            VStack(alignment: .leading, spacing: 3) {
                Text(payment.patient?.name ?? payment.senderSummary)
                    .font(.body.weight(.medium))
                HStack(spacing: 4) {
                    Text(payment.date.formatted(date: .abbreviated, time: .shortened))
                    if payment.isLinked, let sender = payment.senderName {
                        Text("· \(sender)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let comment = payment.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let accountLabel = payment.accountLabel {
                    Label(accountLabel, systemImage: "creditcard")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if !payment.isLinked {
                    Text("Needs linking")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let convertedMinor {
                    MoneyText(minor: convertedMinor, currency: displayCurrency)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.green)
                    MoneyText(minor: payment.amountMinor, currency: payment.currencyCode)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    MoneyText(minor: payment.amountMinor, currency: payment.currencyCode)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
        }
    }
}
