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
                Section(payment.isLinked ? "Move to another patient" : "Link to patient") {
                    ForEach(patients) { patient in
                        Button {
                            PaymentLinker.link(payment, to: patient, rememberPayer: rememberPayer, context: context)
                            dismiss()
                        } label: {
                            HStack {
                                Text(patient.name)
                                Spacer()
                                if payment.patient === patient {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                } else {
                                    BalanceChip(balance: patient.balance, currency: patient.currencyCode)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if payment.isLinked {
                    Section {
                        Button("Unlink from patient", role: .destructive) {
                            payment.patient = nil
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(payment.isLinked ? "Relink payment" : "Link payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
