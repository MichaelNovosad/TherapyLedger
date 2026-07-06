import SwiftUI
import SwiftData

struct SlotEditorSheet: View {
    let patient: Patient
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var frequency: SlotFrequency = .weekly
    @State private var weekday = 2
    @State private var dayOfMonth = 1
    @State private var time = Calendar.current.date(from: DateComponents(hour: 10, minute: 0)) ?? .now
    @State private var durationMinutes = 50

    var body: some View {
        NavigationStack {
            Form {
                Picker("Repeats", selection: $frequency) {
                    ForEach(SlotFrequency.allCases) { frequency in
                        Text(frequency.label).tag(frequency)
                    }
                }
                switch frequency {
                case .weekly, .biweekly:
                    Picker("Weekday", selection: $weekday) {
                        ForEach(1...7, id: \.self) { day in
                            Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                        }
                    }
                case .monthly:
                    Picker("Day of month", selection: $dayOfMonth) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)").tag(day)
                        }
                    }
                case .daily:
                    EmptyView()
                }
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 20...180, step: 5)
                if frequency == .biweekly {
                    Text("The first occurrence lands on the next \(Calendar.current.weekdaySymbols[weekday - 1]); following ones repeat every two weeks from there.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Recurring slot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addSlot() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func addSlot() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        context.insert(RecurringSlot(
            weekday: weekday,
            hour: components.hour ?? 10,
            minute: components.minute ?? 0,
            durationMinutes: durationMinutes,
            patient: patient,
            frequency: frequency,
            anchorDate: .now,
            dayOfMonth: dayOfMonth
        ))
        SchedulingService.materializeUpcomingSessions(context: context)
        dismiss()
    }
}
