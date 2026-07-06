import SwiftUI
import SwiftData

struct PaymentEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Patient> { !$0.isArchived }, sort: \Patient.name)
    private var patients: [Patient]

    @State private var selectedPatient: Patient?
    @State private var amount: Decimal?
    @State private var date: Date = .now
    @State private var comment = ""

    init(preselectedPatient: Patient? = nil) {
        _selectedPatient = State(initialValue: preselectedPatient)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Patient", selection: $selectedPatient) {
                    Text("None").tag(nil as Patient?)
                    ForEach(patients) { patient in
                        Text(patient.name).tag(patient as Patient?)
                    }
                }
                TextField("Amount, ₴", value: $amount, format: .number)
                    .keyboardType(.decimalPad)
                DatePicker("Date", selection: $date)
                TextField("Comment", text: $comment, axis: .vertical)
            }
            .navigationTitle("New payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled((amount ?? 0) <= 0)
                }
            }
        }
    }

    private func save() {
        guard let amount, amount > 0 else { return }
        context.insert(Payment(
            date: date,
            amountMinor: Money.minorUnits(from: amount),
            currencyCode: selectedPatient?.currencyCode ?? "UAH",
            source: .manual,
            comment: comment.isEmpty ? nil : comment,
            patient: selectedPatient
        ))
        dismiss()
    }
}
