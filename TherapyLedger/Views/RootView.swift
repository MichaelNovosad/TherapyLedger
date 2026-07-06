import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("monobank.accountId") private var accountId = ""
    @AppStorage("monobank.autoSync") private var autoSync = true
    @AppStorage("monobank.lastSyncTimestamp") private var lastSyncTimestamp = 0.0

    var body: some View {
        TabView {
            Tab("Calendar", systemImage: "calendar") {
                CalendarScreen()
            }
            Tab("Patients", systemImage: "person.2") {
                PatientsListView()
            }
            Tab("Payments", systemImage: "creditcard") {
                PaymentsScreen()
            }
            Tab("Reports", systemImage: "chart.bar") {
                ReportsScreen()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsScreen()
            }
        }
        .task {
            SchedulingService.materializeUpcomingSessions(context: context)
            await autoSyncIfNeeded()
        }
    }

    private func autoSyncIfNeeded() async {
        guard autoSync,
              !accountId.isEmpty,
              let token = KeychainStore.load(key: KeychainStore.monobankTokenKey) else { return }
        // Personal API allows 1 request/min; don't re-sync on every foreground.
        let lastSync = Date(timeIntervalSince1970: lastSyncTimestamp)
        guard Date().timeIntervalSince(lastSync) > 600 else { return }
        if (try? await MonobankSyncService.sync(context: context, token: token, accountId: accountId)) != nil {
            lastSyncTimestamp = Date().timeIntervalSince1970
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Patient.self, TherapySession.self, Payment.self, PayerAlias.self, RecurringSlot.self], inMemory: true)
}
