import Foundation
import SwiftData
@testable import TherapyLedger

func makeInMemoryContext() throws -> ModelContext {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: Patient.self, TherapySession.self, Payment.self, PayerAlias.self, RecurringSlot.self,
        configurations: config
    )
    return ModelContext(container)
}

func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}
