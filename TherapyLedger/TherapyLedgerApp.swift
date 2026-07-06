import SwiftUI
import SwiftData

@main
struct TherapyLedgerApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: Patient.self, TherapySession.self, Payment.self, PayerAlias.self, RecurringSlot.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
