import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("monobank.accountId") private var accountId = ""
    @AppStorage("monobank.accountLabel") private var accountLabel = ""
    @AppStorage("monobank.autoSync") private var autoSync = true
    @AppStorage("monobank.lastSyncTimestamp") private var lastSyncTimestamp = 0.0

    private enum AppTab: Hashable {
        case calendar, patients, reports, settings
    }

    @State private var selectedTab: AppTab = .calendar

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Calendar", systemImage: "calendar", value: AppTab.calendar) {
                CalendarScreen()
            }
            Tab("Patients", systemImage: "person.2", value: AppTab.patients) {
                PatientsListView()
            }
            Tab("Reports", systemImage: "chart.bar", value: AppTab.reports) {
                ReportsScreen()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsScreen()
            }
        }
        .task {
            await refresh()
            await autoSyncIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refresh() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCalendarTab)) { _ in
            selectedTab = .calendar
        }
    }

    private func refresh() async {
        SchedulingService.materializeUpcomingSessions(context: context)
        SchedulingService.autoCompleteIfEnabled(context: context)
        await NotificationService.refresh(context: context)
    }

    private func autoSyncIfNeeded() async {
        guard autoSync,
              !accountId.isEmpty,
              let token = KeychainStore.load(key: KeychainStore.monobankTokenKey) else { return }
        // Personal API allows 1 request/min; don't re-sync on every foreground.
        let lastSync = Date(timeIntervalSince1970: lastSyncTimestamp)
        guard Date().timeIntervalSince(lastSync) > 600 else { return }
        let result = try? await MonobankSyncService.sync(
            context: context,
            token: token,
            accountId: accountId,
            accountLabel: accountLabel.isEmpty ? nil : accountLabel
        )
        if result != nil {
            lastSyncTimestamp = Date().timeIntervalSince1970
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Patient.self, TherapySession.self, Payment.self, PayerAlias.self, RecurringSlot.self], inMemory: true)
}
