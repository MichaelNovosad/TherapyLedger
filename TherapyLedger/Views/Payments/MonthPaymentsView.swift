import SwiftUI
import SwiftData

/// All received transactions of one month, grouped by day, with optional
/// display-currency conversion at each day's official NBU rate.
struct MonthPaymentsView: View {
    let month: Date

    @Environment(\.modelContext) private var context
    @Query(sort: \Payment.date, order: .reverse) private var allPayments: [Payment]
    @AppStorage("monobank.accountId") private var accountId = ""
    @AppStorage("monobank.accountLabel") private var accountLabel = ""
    @AppStorage("monobank.lastSyncTimestamp") private var lastSyncTimestamp = 0.0

    @State private var displayCurrency = "UAH"
    @State private var rates: [Date: Decimal] = [:]
    @State private var ratesUnavailable = false
    @State private var paymentToLink: Payment?
    @State private var showingManualEntry = false
    @State private var isSyncing = false
    @State private var syncError: String?

    private static let currencies = ["UAH", "USD", "EUR"]
    private var calendar: Calendar { .current }

    private var monthPayments: [Payment] {
        allPayments.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    private var dayGroups: [(day: Date, payments: [Payment])] {
        Dictionary(grouping: monthPayments) { calendar.startOfDay(for: $0.date) }
            .map { (day: $0.key, payments: $0.value) }
            .sorted { $0.day > $1.day }
    }

    private var totalMinorUAH: Int {
        monthPayments.filter { $0.currencyCode == "UAH" }.reduce(0) { $0 + $1.amountMinor }
    }

    private var convertedTotalMinor: Int? {
        guard displayCurrency != "UAH" else { return nil }
        var total = 0
        for payment in monthPayments {
            guard let converted = convertedMinor(for: payment) else { return nil }
            total += converted
        }
        return total
    }

    var body: some View {
        List {
            summarySection
            ForEach(dayGroups, id: \.day) { group in
                Section {
                    ForEach(group.payments) { payment in
                        PaymentRow(
                            payment: payment,
                            convertedMinor: convertedMinor(for: payment),
                            displayCurrency: displayCurrency
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            paymentToLink = payment
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                context.delete(payment)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                paymentToLink = payment
                            } label: {
                                Label("Relink", systemImage: "link")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(group.day.formatted(.dateTime.weekday(.wide).day().month()))
                        Spacer()
                        if displayCurrency != "UAH" {
                            if let rate = rates[group.day] {
                                Text("\(rate.formatted(.number.precision(.fractionLength(2)))) ₴/\(displayCurrency)")
                            } else if ratesUnavailable {
                                Text("rate unavailable")
                            }
                        }
                    }
                }
            }
            if monthPayments.isEmpty {
                ContentUnavailableView(
                    "No payments",
                    systemImage: "creditcard",
                    description: Text("Nothing was received in \(month.formatted(.dateTime.month(.wide).year())).")
                )
            }
        }
        .navigationTitle(month.formatted(.dateTime.month(.wide).year()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await syncNow() }
                } label: {
                    if isSyncing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isSyncing || accountId.isEmpty)
                .accessibilityLabel("Sync with Monobank")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingManualEntry = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add payment manually")
            }
        }
        .sheet(item: $paymentToLink) { payment in
            LinkPaymentSheet(payment: payment)
        }
        .sheet(isPresented: $showingManualEntry) {
            PaymentEditorView()
        }
        .alert("Sync failed", isPresented: .constant(syncError != nil)) {
            Button("OK") { syncError = nil }
        } message: {
            Text(syncError ?? "")
        }
        .task(id: displayCurrency) {
            await loadRatesIfNeeded()
        }
    }

    private var summarySection: some View {
        Section {
            Picker("Show amounts in", selection: $displayCurrency) {
                ForEach(Self.currencies, id: \.self) { currency in
                    Text(currency).tag(currency)
                }
            }
            .pickerStyle(.segmented)

            LabeledContent("Received (UAH)") {
                MoneyText(minor: totalMinorUAH)
                    .fontWeight(.semibold)
            }
            if displayCurrency != "UAH" {
                LabeledContent("≈ in \(displayCurrency)") {
                    if let convertedTotalMinor {
                        MoneyText(minor: convertedTotalMinor, currency: displayCurrency)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    } else {
                        Text(ratesUnavailable ? "rates unavailable" : "…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } footer: {
            if displayCurrency != "UAH" {
                Text("Converted at the official NBU rate of each transaction's day, so a payment on the 6th and one on the 7th use their own daily rates.")
            }
        }
    }

    private func convertedMinor(for payment: Payment) -> Int? {
        guard displayCurrency != "UAH" else { return nil }
        if payment.currencyCode == displayCurrency {
            return payment.amountMinor
        }
        guard payment.currencyCode == "UAH",
              let rate = rates[calendar.startOfDay(for: payment.date)] else { return nil }
        return ExchangeRateService.convert(minorUAH: payment.amountMinor, rate: rate)
    }

    private func loadRatesIfNeeded() async {
        guard displayCurrency != "UAH" else { return }
        ratesUnavailable = false
        rates = [:]
        for group in dayGroups {
            do {
                rates[group.day] = try await ExchangeRateService.rate(currency: displayCurrency, on: group.day)
            } catch {
                ratesUnavailable = true
            }
        }
    }

    private func syncNow() async {
        guard let token = KeychainStore.load(key: KeychainStore.monobankTokenKey), !accountId.isEmpty else {
            syncError = "Connect your Monobank account in Settings first."
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            _ = try await MonobankSyncService.sync(
                context: context,
                token: token,
                accountId: accountId,
                accountLabel: accountLabel.isEmpty ? nil : accountLabel
            )
            lastSyncTimestamp = Date().timeIntervalSince1970
        } catch {
            syncError = error.localizedDescription
        }
    }
}
