import SwiftUI
import SwiftData

struct PaymentsScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Payment.date, order: .reverse) private var payments: [Payment]
    @AppStorage("monobank.accountId") private var accountId = ""
    @AppStorage("monobank.lastSyncTimestamp") private var lastSyncTimestamp = 0.0

    @State private var showingManualEntry = false
    @State private var paymentToLink: Payment?
    @State private var isSyncing = false
    @State private var syncMessage: String?
    @State private var syncError: String?

    private var unlinked: [Payment] { payments.filter { !$0.isLinked } }

    private var monthGroups: [(month: Date, payments: [Payment])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: payments.filter(\.isLinked)) { payment in
            calendar.dateInterval(of: .month, for: payment.date)?.start ?? payment.date
        }
        return grouped
            .map { (month: $0.key, payments: $0.value) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        NavigationStack {
            List {
                if payments.isEmpty {
                    ContentUnavailableView(
                        "No payments yet",
                        systemImage: "creditcard",
                        description: Text("Connect Monobank in Settings or add a payment manually.")
                    )
                }
                if !unlinked.isEmpty {
                    Section {
                        ForEach(unlinked) { payment in
                            Button {
                                paymentToLink = payment
                            } label: {
                                PaymentRow(payment: payment)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Label("Needs linking (\(unlinked.count))", systemImage: "link.badge.plus")
                    } footer: {
                        Text("Tap a payment to link it to a patient. The payer is remembered for next time.")
                    }
                }
                ForEach(monthGroups, id: \.month) { group in
                    Section {
                        ForEach(group.payments) { payment in
                            PaymentRow(payment: payment)
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
                            Text(group.month.formatted(.dateTime.month(.wide).year()))
                            Spacer()
                            Text(Money.format(group.payments.reduce(0) { $0 + $1.amountMinor }))
                        }
                    }
                }
            }
            .navigationTitle("Payments")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
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
            .sheet(isPresented: $showingManualEntry) {
                PaymentEditorView()
            }
            .sheet(item: $paymentToLink) { payment in
                LinkPaymentSheet(payment: payment)
            }
            .alert("Sync failed", isPresented: .constant(syncError != nil)) {
                Button("OK") { syncError = nil }
            } message: {
                Text(syncError ?? "")
            }
            .overlay(alignment: .bottom) {
                if let syncMessage {
                    Text(syncMessage)
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 8)
                        .task {
                            try? await Task.sleep(for: .seconds(3))
                            self.syncMessage = nil
                        }
                }
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
            let result = try await MonobankSyncService.sync(context: context, token: token, accountId: accountId)
            lastSyncTimestamp = Date().timeIntervalSince1970
            syncMessage = result.summary
        } catch {
            syncError = error.localizedDescription
        }
    }
}

struct PaymentRow: View {
    let payment: Payment

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
            }
            Spacer()
            MoneyText(minor: payment.amountMinor, currency: payment.currencyCode)
                .font(.body.weight(.semibold))
                .foregroundStyle(.green)
        }
    }
}

#Preview {
    PaymentsScreen()
        .modelContainer(for: [Patient.self, TherapySession.self, Payment.self, PayerAlias.self, RecurringSlot.self], inMemory: true)
}
