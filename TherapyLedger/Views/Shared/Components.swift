import SwiftUI

extension SessionStatus {
    var tint: Color {
        switch self {
        case .scheduled: .blue
        case .completed: .green
        case .missed: .red
        case .cancelled: .gray
        }
    }
}

struct StatusBadge: View {
    let status: SessionStatus
    var wasRescheduled = false

    var body: some View {
        HStack(spacing: 4) {
            Label(status.label, systemImage: status.systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(status.tint)
            if wasRescheduled {
                Image(systemName: "arrow.uturn.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Rescheduled")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(status.tint.opacity(0.12), in: Capsule())
    }
}

struct BalanceChip: View {
    let balance: PatientBalance
    var currency = "UAH"

    var body: some View {
        if balance.debtMinor > 0 {
            Text("Owes \(Money.format(balance.debtMinor, currency: currency))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
        } else if balance.creditMinor > 0 {
            Text("Credit \(Money.format(balance.creditMinor, currency: currency))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        } else {
            Text("Settled")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct MoneyText: View {
    let minor: Int
    var currency = "UAH"

    var body: some View {
        Text(Money.format(minor, currency: currency))
            .monospacedDigit()
    }
}
