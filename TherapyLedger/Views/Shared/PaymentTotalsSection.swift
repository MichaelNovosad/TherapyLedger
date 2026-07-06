import SwiftUI

/// Browsable received-payment totals: "Total in June 2026: ₴4,000.00",
/// switchable between month and year granularity with chevrons.
struct PaymentTotalsSection: View {
    let payments: [Payment]
    var currency = "UAH"

    private enum Granularity: String, CaseIterable, Identifiable {
        case month, year
        var id: String { rawValue }
        var label: String { self == .month ? "Month" : "Year" }
        var component: Calendar.Component { self == .month ? .month : .year }
    }

    @State private var granularity: Granularity = .month
    @State private var period: Date = .now

    private var calendar: Calendar { .current }

    private var periodLabel: String {
        switch granularity {
        case .month: period.formatted(.dateTime.month(.wide).year())
        case .year: period.formatted(.dateTime.year())
        }
    }

    private var total: Int {
        Ledger.receivedTotal(payments: payments, in: period, granularity: granularity.component)
    }

    private var isCurrentPeriod: Bool {
        calendar.isDate(period, equalTo: .now, toGranularity: granularity.component)
    }

    var body: some View {
        Section("Payment statistics") {
            Picker("Granularity", selection: $granularity) {
                ForEach(Granularity.allCases) { granularity in
                    Text(granularity.label).tag(granularity)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button {
                    shift(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Previous \(granularity.label)")

                Spacer()
                VStack(spacing: 2) {
                    Text("Total in \(periodLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    MoneyText(minor: total, currency: currency)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(total > 0 ? .primary : .secondary)
                }
                Spacer()

                Button {
                    shift(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(isCurrentPeriod)
                .accessibilityLabel("Next \(granularity.label)")
            }
        }
    }

    private func shift(by value: Int) {
        if let newPeriod = calendar.date(byAdding: granularity.component, value: value, to: period) {
            period = newPeriod
        }
    }
}
