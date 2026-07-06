import SwiftUI
import SwiftData

struct SessionDetailView: View {
    @Bindable var session: TherapySession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showingReschedule = false
    @State private var confirmingEndSeries = false
    @AppStorage(TimeZoneSettings.dualEnabledKey) private var dualTimeZones = false
    @AppStorage(TimeZoneSettings.primaryKey) private var primaryZone = TimeZoneSettings.defaultIdentifier
    @AppStorage(TimeZoneSettings.secondaryKey) private var secondaryZone = TimeZoneSettings.defaultIdentifier

    private var currency: String { session.patient?.currencyCode ?? "UAH" }

    private var paymentStatus: SessionPaymentStatus {
        guard let patient = session.patient else { return .awaiting }
        return Ledger.paymentStatuses(sessions: patient.sessions, payments: patient.payments)[ObjectIdentifier(session)] ?? .awaiting
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Patient", value: session.patient?.name ?? "—")
                LabeledContent("Date") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(session.scheduledAt.formatted(date: .abbreviated, time: dualTimeZones ? .omitted : .shortened))
                        if dualTimeZones {
                            Text(TimeZoneSettings.dualLabel(session.scheduledAt, primary: primaryZone, secondary: secondaryZone))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("Duration", value: "\(session.durationMinutes) min")
                LabeledContent("Fee") {
                    MoneyText(minor: session.feeMinor, currency: currency)
                }
                if let slot = session.slot {
                    LabeledContent("Series", value: slot.scheduleLabel)
                }
            }

            Section("Status") {
                Picker("Status", selection: $session.status) {
                    ForEach(SessionStatus.allCases) { status in
                        Text(status.label).tag(status)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    showingReschedule = true
                } label: {
                    Label("Reschedule…", systemImage: "calendar.badge.clock")
                }
            }

            if session.isBillable {
                paymentSection
            }

            if session.wasRescheduled {
                Section("Reschedule history") {
                    // A session can be moved to the same date twice, so key by position.
                    ForEach(Array(session.previousDates.enumerated()), id: \.offset) { _, date in
                        Label {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                        } icon: {
                            Image(systemName: "arrow.uturn.right")
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Notes") {
                TextField("Notes", text: $session.notes, axis: .vertical)
                    .lineLimit(3...8)
            }

            Section {
                Button("End series from here", role: .destructive) {
                    confirmingEndSeries = true
                }
                Button("Delete session", role: .destructive) {
                    SchedulingService.delete(session: session, context: context)
                    dismiss()
                }
            } footer: {
                Text("Deleting a future scheduled session removes only that occurrence — the series continues and will not recreate it. Ending the series removes this and all future scheduled sessions and pauses the recurring slot. Past completed or missed sessions are kept.")
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingReschedule) {
            RescheduleSheet(session: session)
        }
        .confirmationDialog(
            "Delete this and all future scheduled sessions?",
            isPresented: $confirmingEndSeries,
            titleVisibility: .visible
        ) {
            Button("End series", role: .destructive) {
                SchedulingService.endSeries(after: session, context: context)
                dismiss()
            }
        }
    }

    private var paymentSection: some View {
        Section {
            switch paymentStatus {
            case .paid(let date):
                Label {
                    Text("Paid — received \(date.formatted(date: .abbreviated, time: .omitted))")
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                }
                .foregroundStyle(.green)
            case .delayed(let date, let weeksLate):
                Label {
                    Text("Delayed — received \(date.formatted(date: .abbreviated, time: .omitted)), \(weeksLate) week\(weeksLate == 1 ? "" : "s") late")
                } icon: {
                    Image(systemName: "clock.badge.exclamationmark.fill")
                }
                .foregroundStyle(.orange)
            case .awaiting:
                Label("Awaiting payment", systemImage: "hourglass")
                    .foregroundStyle(.red)
            }
            if let patient = session.patient {
                LabeledContent("Patient balance") {
                    BalanceChip(balance: patient.balance, currency: currency)
                }
            }
        } header: {
            Text("Payment")
        } footer: {
            Text("A session counts as paid when payments received in its week cover it. Payments arriving in later weeks mark it as delayed.")
        }
    }
}
