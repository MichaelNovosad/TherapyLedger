import SwiftUI
import SwiftData

struct ReportsScreen: View {
    @Query private var sessions: [TherapySession]
    @Query private var payments: [Payment]
    @Query(sort: \Patient.name) private var patients: [Patient]
    @State private var year = Calendar.current.component(.year, from: .now)

    private var summaries: [MonthSummary] {
        Ledger.monthlySummaries(sessions: sessions, payments: payments, year: year)
    }

    private var activeMonths: [MonthSummary] {
        summaries.filter { $0.billedMinor > 0 || $0.receivedMinor > 0 || $0.completedCount > 0 || $0.missedCount > 0 }
    }

    private var debtors: [Patient] {
        patients
            .filter { $0.balance.debtMinor > 0 }
            .sorted { $0.balance.debtMinor > $1.balance.debtMinor }
    }

    var body: some View {
        NavigationStack {
            List {
                yearTotalsSection
                monthsSection
                debtsSection
            }
            .navigationTitle("Reports")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        year -= 1
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Previous year")
                }
                ToolbarItem(placement: .principal) {
                    Text(String(year))
                        .font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        year += 1
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(year >= Calendar.current.component(.year, from: .now))
                    .accessibilityLabel("Next year")
                }
            }
        }
    }

    private var yearTotalsSection: some View {
        Section("Year \(String(year))") {
            let totals = Ledger.yearTotals(summaries)
            LabeledContent("Billed") {
                MoneyText(minor: totals.billedMinor)
            }
            LabeledContent("Received") {
                MoneyText(minor: totals.receivedMinor)
                    .foregroundStyle(.green)
            }
            let gap = totals.billedMinor - totals.receivedMinor
            if gap > 0 {
                LabeledContent("Not yet received") {
                    MoneyText(minor: gap)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var monthsSection: some View {
        Section("By month") {
            if activeMonths.isEmpty {
                Text("No activity in \(String(year))")
                    .foregroundStyle(.secondary)
            }
            ForEach(activeMonths) { summary in
                NavigationLink {
                    MonthPaymentsView(month: monthDate(of: summary))
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(summary.monthName)
                                .font(.body.weight(.medium))
                            Spacer()
                            if summary.receivedMinor < summary.billedMinor {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                    .accessibilityLabel("Payments behind billing")
                            }
                        }
                        HStack {
                            Text("\(summary.completedCount) completed · \(summary.missedCount) missed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Billed \(Money.format(summary.billedMinor))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Received \(Money.format(summary.receivedMinor))")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(summary.receivedMinor >= summary.billedMinor ? .green : .orange)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func monthDate(of summary: MonthSummary) -> Date {
        Calendar.current.date(from: DateComponents(year: summary.year, month: summary.month, day: 1)) ?? .now
    }

    private var debtsSection: some View {
        Section {
            if debtors.isEmpty {
                Label("Everyone is settled", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
            ForEach(debtors) { patient in
                NavigationLink {
                    PatientDetailView(patient: patient)
                } label: {
                    HStack {
                        Text(patient.name)
                        Spacer()
                        MoneyText(minor: patient.balance.debtMinor, currency: patient.currencyCode)
                            .foregroundStyle(.red)
                    }
                }
            }
            if debtors.count > 1 {
                LabeledContent("Total outstanding") {
                    MoneyText(minor: debtors.reduce(0) { $0 + $1.balance.debtMinor })
                        .foregroundStyle(.red)
                        .fontWeight(.semibold)
                }
            }
        } header: {
            Text("Outstanding debts")
        } footer: {
            Text("All-time balance per patient: billable sessions minus received payments.")
        }
    }
}

#Preview {
    ReportsScreen()
        .modelContainer(for: [Patient.self, TherapySession.self, Payment.self, PayerAlias.self, RecurringSlot.self], inMemory: true)
}
