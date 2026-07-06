import SwiftUI
import SwiftData

struct AddSessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Patient> { !$0.isArchived }, sort: \Patient.name)
    private var patients: [Patient]

    @State private var selectedPatient: Patient?
    @State private var date: Date
    @State private var durationMinutes = 50
    @State private var fee: Decimal?

    init(initialDate: Date) {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: initialDate)
        let now = Calendar.current.dateComponents([.hour], from: .now)
        components.hour = now.hour
        components.minute = 0
        _date = State(initialValue: Calendar.current.date(from: components) ?? initialDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Patient", selection: $selectedPatient) {
                    Text("Choose…").tag(nil as Patient?)
                    ForEach(patients) { patient in
                        Text(patient.name).tag(patient as Patient?)
                    }
                }
                DatePicker("Date & time", selection: $date)
                Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 20...180, step: 5)
                TextField("Fee", value: $fee, format: .number)
                    .keyboardType(.decimalPad)
            }
            .navigationTitle("New session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addSession()
                    }
                    .disabled(selectedPatient == nil)
                }
            }
            .onChange(of: selectedPatient) {
                if let patient = selectedPatient {
                    fee = Money.major(from: patient.sessionFeeMinor)
                }
            }
        }
    }

    private func addSession() {
        guard let patient = selectedPatient else { return }
        let feeMinor = fee.map(Money.minorUnits(from:)) ?? patient.sessionFeeMinor
        context.insert(TherapySession(
            patient: patient,
            scheduledAt: date,
            durationMinutes: durationMinutes,
            feeMinor: feeMinor
        ))
        dismiss()
    }
}
