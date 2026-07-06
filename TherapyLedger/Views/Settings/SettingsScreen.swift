import SwiftUI
import SwiftData

struct SettingsScreen: View {
    @Environment(\.modelContext) private var context
    @AppStorage("monobank.accountId") private var accountId = ""
    @AppStorage("monobank.accountLabel") private var accountLabel = ""
    @AppStorage("monobank.autoSync") private var autoSync = true
    @AppStorage("monobank.lastSyncTimestamp") private var lastSyncTimestamp = 0.0

    @AppStorage(SettingsKeys.remindersEnabled) private var remindersEnabled = false
    @AppStorage(SettingsKeys.reminderStyle) private var reminderStyleRaw = ReminderStyle.dailySummary.rawValue
    @AppStorage(SettingsKeys.reminderDailyHour) private var reminderDailyHour = 20
    @AppStorage(SettingsKeys.reminderDailyMinute) private var reminderDailyMinute = 0
    @AppStorage(SettingsKeys.reminderSessionDelayMinutes) private var reminderDelayMinutes = 10
    @AppStorage(SettingsKeys.autoCompleteEnabled) private var autoCompleteEnabled = false
    @AppStorage(SettingsKeys.autoCompleteStart) private var autoCompleteStart = 0.0
    @AppStorage(TimeZoneSettings.dualEnabledKey) private var dualTimeZones = false
    @AppStorage(TimeZoneSettings.primaryKey) private var primaryZone = TimeZoneSettings.defaultIdentifier
    @AppStorage(TimeZoneSettings.secondaryKey) private var secondaryZone = TimeZoneSettings.defaultIdentifier

    @State private var hasToken = KeychainStore.load(key: KeychainStore.monobankTokenKey) != nil
    @State private var tokenInput = ""
    @State private var isWorking = false
    @State private var isSyncing = false
    @State private var errorMessage: String?
    @State private var syncMessage: String?
    @State private var pickerAccounts: [MonoAccount] = []
    @State private var showAccountPicker = false
    @State private var isBackfilling = false
    @State private var backfillProgress: String?
    @AppStorage(SettingsKeys.monobankHistoryOldest) private var historyOldest = 0.0

    private var yearHistoryLoaded: Bool {
        historyOldest > 0
            && Date(timeIntervalSince1970: historyOldest) <= Date.now.addingTimeInterval(-360 * 86_400)
    }

    private var reminderStyle: ReminderStyle {
        ReminderStyle(rawValue: reminderStyleRaw) ?? .dailySummary
    }

    var body: some View {
        NavigationStack {
            Form {
                monobankSection
                remindersSection
                sessionsSection
                timeZonesSection
                privacySection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationDestination(isPresented: $showAccountPicker) {
                AccountPickerView(initialAccounts: pickerAccounts)
            }
            .alert("Monobank", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: remindersEnabled) { _, enabled in
                if enabled {
                    Task {
                        if await NotificationService.requestAuthorization() {
                            await NotificationService.refresh(context: context)
                        } else {
                            remindersEnabled = false
                            errorMessage = "Notifications are disabled for TherapyLedger in iOS Settings."
                        }
                    }
                } else {
                    Task { await NotificationService.refresh(context: context) }
                }
            }
            .onChange(of: reminderStyleRaw) { rescheduleReminders() }
            .onChange(of: reminderDailyHour) { rescheduleReminders() }
            .onChange(of: reminderDailyMinute) { rescheduleReminders() }
            .onChange(of: reminderDelayMinutes) { rescheduleReminders() }
        }
    }

    // MARK: Monobank

    private var monobankSection: some View {
        Section {
            if !hasToken {
                SecureField("Personal API token", text: $tokenInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    Task { await connect() }
                } label: {
                    if isWorking {
                        HStack {
                            ProgressView()
                            Text("Connecting…")
                        }
                    } else {
                        Label("Connect", systemImage: "link")
                    }
                }
                .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            } else {
                NavigationLink {
                    AccountPickerView()
                } label: {
                    LabeledContent("Account") {
                        Text(accountId.isEmpty ? "Choose…" : accountLabel)
                            .foregroundStyle(accountId.isEmpty ? .red : .secondary)
                    }
                }
                if !accountId.isEmpty {
                    if lastSyncTimestamp > 0 {
                        LabeledContent("Last sync") {
                            Text(Date(timeIntervalSince1970: lastSyncTimestamp), format: .relative(presentation: .named))
                        }
                    }
                    Toggle("Sync on launch", isOn: $autoSync)
                    Button {
                        Task { await syncNow() }
                    } label: {
                        if isSyncing {
                            HStack {
                                ProgressView()
                                Text("Syncing…")
                            }
                        } else {
                            Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(isSyncing)
                    if yearHistoryLoaded {
                        Label("Last year of history loaded", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    } else {
                        Button {
                            Task { await loadYearHistory() }
                        } label: {
                            if isBackfilling {
                                HStack {
                                    ProgressView()
                                    Text(backfillProgress ?? "Loading history…")
                                }
                            } else {
                                Label(
                                    historyOldest > 0 ? "Continue loading year history" : "Load last year of history",
                                    systemImage: "clock.arrow.circlepath"
                                )
                            }
                        }
                        .disabled(isSyncing || isBackfilling)
                    }
                    if let syncMessage {
                        Text(syncMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Disconnect", role: .destructive) {
                    disconnect()
                }
            }
        } header: {
            Text("Monobank")
        } footer: {
            if !hasToken {
                Text("Get a free personal token at api.monobank.ua — log in with the Monobank app, then paste the token here. It is stored only in the device Keychain.")
            } else if !yearHistoryLoaded && !accountId.isEmpty {
                Text("Loading a year of history takes about 12 minutes — the bank allows one request per minute. Keep the app open; if interrupted, it continues where it stopped.")
            }
        }
    }

    // MARK: Reminders

    private var remindersSection: some View {
        Section {
            Toggle("Review reminders", isOn: $remindersEnabled)
            if remindersEnabled {
                Picker("Remind", selection: $reminderStyleRaw) {
                    ForEach(ReminderStyle.allCases) { style in
                        Text(style.label).tag(style.rawValue)
                    }
                }
                if reminderStyle.includesDaily {
                    DatePicker("Daily reminder at", selection: dailyTimeBinding, displayedComponents: .hourAndMinute)
                }
                if reminderStyle.includesPerSession {
                    Picker("After session ends", selection: $reminderDelayMinutes) {
                        ForEach([0, 5, 10, 15, 30, 60], id: \.self) { minutes in
                            Text(minutes == 0 ? "Immediately" : "\(minutes) min later").tag(minutes)
                        }
                    }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("A tap on a reminder opens the calendar to review ended sessions. Notifications never include patient names.")
        }
    }

    private var dailyTimeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: reminderDailyHour, minute: reminderDailyMinute)) ?? .now
        } set: { newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderDailyHour = components.hour ?? 20
            reminderDailyMinute = components.minute ?? 0
        }
    }

    private func rescheduleReminders() {
        Task { await NotificationService.refresh(context: context) }
    }

    // MARK: Sessions

    private var sessionsSection: some View {
        Section {
            Toggle("Auto-complete ended sessions", isOn: $autoCompleteEnabled)
                .onChange(of: autoCompleteEnabled) { _, enabled in
                    if enabled {
                        autoCompleteStart = Date.now.timeIntervalSince1970
                        SchedulingService.autoCompleteIfEnabled(context: context)
                    }
                }
            if autoCompleteEnabled, autoCompleteStart > 0 {
                LabeledContent("Active since") {
                    Text(Date(timeIntervalSince1970: autoCompleteStart).formatted(date: .abbreviated, time: .shortened))
                }
            }
        } header: {
            Text("Sessions")
        } footer: {
            Text("Starts from the moment you switch it on: sessions scheduled from that date are marked completed automatically, each one only after its own end time has passed. Earlier sessions are never touched.")
        }
    }

    // MARK: Time zones

    private var timeZonesSection: some View {
        Section {
            Toggle("Show two time zones", isOn: $dualTimeZones)
            if dualTimeZones {
                NavigationLink {
                    TimeZonePickerView(title: "Primary zone", selection: $primaryZone)
                } label: {
                    LabeledContent("Primary", value: TimeZoneSettings.cityName(primaryZone))
                }
                NavigationLink {
                    TimeZonePickerView(title: "Second zone", selection: $secondaryZone)
                } label: {
                    LabeledContent("Second", value: TimeZoneSettings.cityName(secondaryZone))
                }
            }
        } header: {
            Text("Time zones")
        } footer: {
            Text("Session times in the calendar and session screen are shown in both zones.")
        }
    }

    // MARK: Other sections

    private var privacySection: some View {
        Section("Privacy") {
            Label {
                Text("All data stays on this device. Nothing is uploaded anywhere; the only network calls are to the Monobank API.")
                    .font(.footnote)
            } icon: {
                Image(systemName: "lock.shield")
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0")
        }
    }

    // MARK: Actions

    private func connect() async {
        let token = tokenInput.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let info = try await MonobankClient(token: token).clientInfo()
            KeychainStore.save(token, key: KeychainStore.monobankTokenKey)
            hasToken = true
            tokenInput = ""
            pickerAccounts = info.accounts
            showAccountPicker = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func disconnect() {
        KeychainStore.delete(key: KeychainStore.monobankTokenKey)
        hasToken = false
        accountId = ""
        accountLabel = ""
        lastSyncTimestamp = 0
        historyOldest = 0
        pickerAccounts = []
    }

    private func loadYearHistory() async {
        guard let token = KeychainStore.load(key: KeychainStore.monobankTokenKey) else {
            errorMessage = "Token missing — reconnect your account."
            return
        }
        isBackfilling = true
        defer {
            isBackfilling = false
            backfillProgress = nil
        }
        do {
            let result = try await MonobankSyncService.backfillYearHistory(
                context: context,
                token: token,
                accountId: accountId,
                accountLabel: accountLabel.isEmpty ? nil : accountLabel
            ) { step, total in
                backfillProgress = "Loading history… \(step) of \(total)"
            }
            syncMessage = "History loaded: \(result.summary)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncNow() async {
        guard let token = KeychainStore.load(key: KeychainStore.monobankTokenKey) else {
            errorMessage = "Token missing — reconnect your account."
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let result = try await MonobankSyncService.sync(
                context: context,
                token: token,
                accountId: accountId,
                accountLabel: accountLabel.isEmpty ? nil : accountLabel
            )
            lastSyncTimestamp = Date().timeIntervalSince1970
            syncMessage = result.summary
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    SettingsScreen()
        .modelContainer(for: [Patient.self, TherapySession.self, Payment.self, PayerAlias.self, RecurringSlot.self], inMemory: true)
}
