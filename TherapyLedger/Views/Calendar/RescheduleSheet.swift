import SwiftUI

struct RescheduleSheet: View {
    let session: TherapySession
    @Environment(\.dismiss) private var dismiss
    @State private var newDate: Date

    init(session: TherapySession) {
        self.session = session
        _newDate = State(initialValue: session.scheduledAt)
    }

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Current") {
                    Text(session.scheduledAt.formatted(date: .abbreviated, time: .shortened))
                }
                DatePicker("New date & time", selection: $newDate)
            }
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        session.reschedule(to: newDate)
                        dismiss()
                    }
                    .disabled(Calendar.current.isDate(newDate, equalTo: session.scheduledAt, toGranularity: .minute))
                }
            }
        }
        .presentationDetents([.medium])
    }
}
