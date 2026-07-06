import SwiftUI
import SwiftData

struct LinkPaymentSheet: View {
    let payment: Payment
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Patient> { !$0.isArchived }, sort: \Patient.name)
    private var patients: [Patient]
    @State private var rememberPayer = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PaymentRow(payment: payment)
                }
                Section {
                    Toggle("Remember this payer", isOn: $rememberPayer)
                } footer: {
                    Text("Future transfers from the same sender will be linked automatically.")
                }
                Section("Link to patient") {
                    ForEach(patients) { patient in
                        Button {
                            link(to: patient)
                        } label: {
                            HStack {
                                Text(patient.name)
                                Spacer()
                                BalanceChip(balance: patient.balance, currency: patient.currencyCode)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Link payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func link(to patient: Patient) {
        payment.patient = patient

        if rememberPayer {
            var newAliases: [PayerAlias] = []
            if let iban = payment.senderIban, !iban.isEmpty {
                newAliases.append(PayerAlias(matchText: iban, kind: .iban, patient: patient))
            }
            if let name = payment.senderName, !name.isEmpty {
                newAliases.append(PayerAlias(matchText: name, kind: .senderName, patient: patient))
            }
            for alias in newAliases {
                context.insert(alias)
            }
            relinkPendingPayments(with: newAliases)
        }
        dismiss()
    }

    /// Apply the just-confirmed aliases to any other unlinked payments.
    private func relinkPendingPayments(with aliases: [PayerAlias]) {
        guard !aliases.isEmpty else { return }
        let pending = (try? context.fetch(
            FetchDescriptor<Payment>(predicate: #Predicate { $0.patient == nil })
        )) ?? []
        for other in pending {
            other.patient = PaymentMatcher.match(
                senderName: other.senderName,
                senderIban: other.senderIban,
                description: other.comment,
                aliases: aliases
            )
        }
    }
}
