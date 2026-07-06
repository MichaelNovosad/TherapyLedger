import SwiftUI
import SwiftData

struct PatientsListView: View {
    @Query(sort: \Patient.name) private var patients: [Patient]
    @State private var showingNewPatient = false

    private var active: [Patient] { patients.filter { !$0.isArchived } }
    private var archived: [Patient] { patients.filter(\.isArchived) }

    var body: some View {
        NavigationStack {
            List {
                if active.isEmpty && archived.isEmpty {
                    ContentUnavailableView(
                        "No patients yet",
                        systemImage: "person.2",
                        description: Text("Add a patient to start scheduling sessions and tracking payments.")
                    )
                }
                ForEach(active) { patient in
                    NavigationLink {
                        PatientDetailView(patient: patient)
                    } label: {
                        PatientRow(patient: patient)
                    }
                }
                if !archived.isEmpty {
                    Section("Archived") {
                        ForEach(archived) { patient in
                            NavigationLink {
                                PatientDetailView(patient: patient)
                            } label: {
                                PatientRow(patient: patient)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Patients")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewPatient = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add patient")
                }
            }
            .sheet(isPresented: $showingNewPatient) {
                PatientEditorView(patient: nil)
            }
        }
    }
}

struct PatientRow: View {
    let patient: Patient

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(patient.name)
                    .font(.body.weight(.medium))
                Text("\(Money.format(patient.sessionFeeMinor, currency: patient.currencyCode)) per session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            BalanceChip(balance: patient.balance, currency: patient.currencyCode)
        }
    }
}

#Preview {
    PatientsListView()
        .modelContainer(for: [Patient.self, TherapySession.self, Payment.self, PayerAlias.self, RecurringSlot.self], inMemory: true)
}
