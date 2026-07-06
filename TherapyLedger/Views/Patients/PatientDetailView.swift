import SwiftUI
import SwiftData

struct PatientDetailView: View {
    @Bindable var patient: Patient
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditor = false
    @State private var showingSlotEditor = false
    @State private var newAliasText = ""

    private var recentSessions: [TherapySession] {
        patient.sessions
            .sorted { $0.scheduledAt > $1.scheduledAt }
            .prefix(10)
            .map { $0 }
    }

    private var recentPayments: [Payment] {
        patient.payments
            .sorted { $0.date > $1.date }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        List {
            balanceSection
            slotsSection
            aliasesSection
            sessionsSection
            paymentsSection
            managementSection
        }
        .navigationTitle(patient.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor) {
            PatientEditorView(patient: patient)
        }
        .sheet(isPresented: $showingSlotEditor) {
            SlotEditorSheet(patient: patient)
        }
    }

    private var balanceSection: some View {
        Section("Balance") {
            let balance = patient.balance
            LabeledContent("Billed") {
                MoneyText(minor: balance.billedMinor, currency: patient.currencyCode)
            }
            LabeledContent("Received") {
                MoneyText(minor: balance.paidMinor, currency: patient.currencyCode)
            }
            LabeledContent(balance.creditMinor > 0 ? "Credit" : "Debt") {
                BalanceChip(balance: balance, currency: patient.currencyCode)
            }
        }
    }

    private var slotsSection: some View {
        Section {
            ForEach(patient.slots.sorted { ($0.weekday, $0.hour, $0.minute) < ($1.weekday, $1.hour, $1.minute) }) { slot in
                HStack {
                    Text("\(slot.weekdayName) \(slot.timeLabel)")
                    Spacer()
                    if !slot.isActive {
                        Text("Paused")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        context.delete(slot)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        slot.isActive.toggle()
                        if slot.isActive {
                            SchedulingService.materializeUpcomingSessions(context: context)
                        }
                    } label: {
                        Label(slot.isActive ? "Pause" : "Resume", systemImage: slot.isActive ? "pause" : "play")
                    }
                }
            }
            Button {
                showingSlotEditor = true
            } label: {
                Label("Add weekly slot", systemImage: "plus")
            }
        } header: {
            Text("Weekly schedule")
        } footer: {
            Text("Slots create sessions in the calendar four weeks ahead.")
        }
    }

    private var aliasesSection: some View {
        Section {
            ForEach(patient.aliases) { alias in
                HStack {
                    Image(systemName: alias.kind == .iban ? "building.columns" : "person.text.rectangle")
                        .foregroundStyle(.secondary)
                    Text(alias.matchText)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        context.delete(alias)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            HStack {
                TextField("Add payer name…", text: $newAliasText)
                Button("Add") {
                    let trimmed = newAliasText.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    context.insert(PayerAlias(matchText: trimmed, kind: .senderName, patient: patient))
                    newAliasText = ""
                }
                .disabled(newAliasText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Payer aliases")
        } footer: {
            Text("Incoming bank transfers from these senders are linked to \(patient.name) automatically.")
        }
    }

    private var sessionsSection: some View {
        Section("Recent sessions") {
            if recentSessions.isEmpty {
                Text("No sessions yet")
                    .foregroundStyle(.secondary)
            }
            ForEach(recentSessions) { session in
                NavigationLink {
                    SessionDetailView(session: session)
                } label: {
                    HStack {
                        Text(session.scheduledAt.formatted(date: .abbreviated, time: .shortened))
                        Spacer()
                        StatusBadge(status: session.status, wasRescheduled: session.wasRescheduled)
                    }
                }
            }
        }
    }

    private var paymentsSection: some View {
        Section("Recent payments") {
            if recentPayments.isEmpty {
                Text("No payments yet")
                    .foregroundStyle(.secondary)
            }
            ForEach(recentPayments) { payment in
                HStack {
                    Text(payment.date.formatted(date: .abbreviated, time: .omitted))
                    Spacer()
                    MoneyText(minor: payment.amountMinor, currency: payment.currencyCode)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var managementSection: some View {
        Section {
            Button(patient.isArchived ? "Unarchive patient" : "Archive patient") {
                patient.isArchived.toggle()
            }
            Button("Delete patient", role: .destructive) {
                context.delete(patient)
                dismiss()
            }
        } footer: {
            Text("Archiving hides the patient from pickers and stops slot generation, but keeps history. Deleting removes sessions; payment records are kept unlinked.")
        }
    }
}
