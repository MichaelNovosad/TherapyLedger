import SwiftUI
import SwiftData

struct PatientEditorView: View {
    let patient: Patient?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var fee: Decimal?
    @State private var chargesForMissed = false
    @State private var notes = ""

    init(patient: Patient?) {
        self.patient = patient
        if let patient {
            _name = State(initialValue: patient.name)
            _fee = State(initialValue: Money.major(from: patient.sessionFeeMinor))
            _chargesForMissed = State(initialValue: patient.chargesForMissedSessions)
            _notes = State(initialValue: patient.notes)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Fee per session, ₴", value: $fee, format: .number)
                        .keyboardType(.decimalPad)
                }
                Section {
                    Toggle("Bill missed sessions", isOn: $chargesForMissed)
                } footer: {
                    Text("When on, a session marked as missed still counts toward what the patient owes.")
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle(patient == nil ? "New patient" : "Edit patient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let feeMinor = fee.map(Money.minorUnits(from:)) ?? 0
        if let patient {
            patient.name = trimmedName
            if patient.sessionFeeMinor != feeMinor {
                SchedulingService.updateFee(for: patient, to: feeMinor)
            }
            patient.chargesForMissedSessions = chargesForMissed
            patient.notes = notes
        } else {
            context.insert(Patient(
                name: trimmedName,
                sessionFeeMinor: feeMinor,
                chargesForMissedSessions: chargesForMissed,
                notes: notes
            ))
        }
        dismiss()
    }
}
