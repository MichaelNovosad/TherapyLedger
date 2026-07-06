import SwiftUI
import SwiftData

struct SessionDetailView: View {
    @Bindable var session: TherapySession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showingReschedule = false

    private var currency: String { session.patient?.currencyCode ?? "UAH" }

    private var isCovered: Bool {
        guard let patient = session.patient else { return false }
        return Ledger.coveredSessions(sessions: patient.sessions, payments: patient.payments)
            .contains(ObjectIdentifier(session))
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Patient", value: session.patient?.name ?? "—")
                LabeledContent("Date") {
                    Text(session.scheduledAt.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Duration", value: "\(session.durationMinutes) min")
                LabeledContent("Fee") {
                    MoneyText(minor: session.feeMinor, currency: currency)
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
                Section("Payment") {
                    if isCovered {
                        Label("Covered by received payments", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not covered yet", systemImage: "hourglass")
                            .foregroundStyle(.orange)
                    }
                    if let patient = session.patient {
                        LabeledContent("Patient balance") {
                            BalanceChip(balance: patient.balance, currency: currency)
                        }
                    }
                }
            }

            if session.wasRescheduled {
                Section("Reschedule history") {
                    ForEach(session.previousDates, id: \.self) { date in
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
                Button("Delete session", role: .destructive) {
                    context.delete(session)
                    dismiss()
                }
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingReschedule) {
            RescheduleSheet(session: session)
        }
    }
}
