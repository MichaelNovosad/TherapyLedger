import SwiftUI
import SwiftData

struct CalendarScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TherapySession.scheduledAt) private var sessions: [TherapySession]
    @State private var displayedMonth: Date = .now
    @State private var selectedDate: Date = .now
    @State private var showingAddSession = false
    @State private var sessionToReschedule: TherapySession?

    private var calendar: Calendar { .current }

    private var sessionsByDay: [Date: [TherapySession]] {
        Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.scheduledAt) }
    }

    private var selectedDaySessions: [TherapySession] {
        (sessionsByDay[calendar.startOfDay(for: selectedDate)] ?? [])
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthHeader
                MonthGrid(
                    month: displayedMonth,
                    selectedDate: $selectedDate,
                    sessionsByDay: sessionsByDay
                )
                .padding(.horizontal, 8)
                Divider()
                daySessionList
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") {
                        withAnimation {
                            displayedMonth = .now
                            selectedDate = .now
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSession = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add session")
                }
            }
            .sheet(isPresented: $showingAddSession) {
                AddSessionView(initialDate: selectedDate)
            }
            .sheet(item: $sessionToReschedule) { session in
                RescheduleSheet(session: session)
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous month")
            Spacer()
            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next month")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func shiftMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            withAnimation { displayedMonth = newMonth }
        }
    }

    private var daySessionList: some View {
        List {
            Section(selectedDate.formatted(date: .complete, time: .omitted)) {
                if selectedDaySessions.isEmpty {
                    Text("No sessions")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(selectedDaySessions) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            SessionRow(session: session)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if session.status != .completed {
                                Button {
                                    session.status = .completed
                                } label: {
                                    Label("Completed", systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if session.status != .missed {
                                Button {
                                    session.status = .missed
                                } label: {
                                    Label("Missed", systemImage: "person.fill.xmark")
                                }
                                .tint(.red)
                            }
                        }
                        .contextMenu {
                            sessionActions(for: session)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func sessionActions(for session: TherapySession) -> some View {
        Button {
            session.status = .completed
        } label: {
            Label("Mark completed", systemImage: "checkmark.circle")
        }
        Button {
            session.status = .missed
        } label: {
            Label("Mark missed", systemImage: "person.fill.xmark")
        }
        Button {
            sessionToReschedule = session
        } label: {
            Label("Reschedule…", systemImage: "calendar.badge.clock")
        }
        Button(role: .destructive) {
            session.status = .cancelled
        } label: {
            Label("Cancel session", systemImage: "xmark.circle")
        }
        if session.status == .scheduled {
            Button(role: .destructive) {
                SchedulingService.skipOccurrence(of: session, context: context)
            } label: {
                Label("Skip this occurrence", systemImage: "calendar.badge.minus")
            }
        }
    }
}

struct SessionRow: View {
    let session: TherapySession
    @AppStorage(TimeZoneSettings.dualEnabledKey) private var dualTimeZones = false
    @AppStorage(TimeZoneSettings.primaryKey) private var primaryZone = TimeZoneSettings.defaultIdentifier
    @AppStorage(TimeZoneSettings.secondaryKey) private var secondaryZone = TimeZoneSettings.defaultIdentifier

    private var timeText: String {
        if dualTimeZones {
            TimeZoneSettings.dualLabel(session.scheduledAt, primary: primaryZone, secondary: secondaryZone)
        } else {
            session.scheduledAt.formatted(date: .omitted, time: .shortened)
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.patient?.name ?? "No patient")
                    .font(.body.weight(.medium))
                Text(timeText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                StatusMenuBadge(session: session)
                MoneyText(minor: session.feeMinor, currency: session.patient?.currencyCode ?? "UAH")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    CalendarScreen()
        .modelContainer(for: [Patient.self, TherapySession.self, Payment.self, PayerAlias.self, RecurringSlot.self], inMemory: true)
}
