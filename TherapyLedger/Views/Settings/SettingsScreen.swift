import SwiftUI
import SwiftData

struct SettingsScreen: View {
    @Environment(\.modelContext) private var context
    @AppStorage("monobank.accountId") private var accountId = ""
    @AppStorage("monobank.accountLabel") private var accountLabel = ""
    @AppStorage("monobank.autoSync") private var autoSync = true
    @AppStorage("monobank.lastSyncTimestamp") private var lastSyncTimestamp = 0.0

    @State private var tokenInput = ""
    @State private var accounts: [MonoAccount] = []
    @State private var isWorking = false
    @State private var isSyncing = false
    @State private var errorMessage: String?
    @State private var syncMessage: String?

    private var isConnected: Bool { !accountId.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                monobankSection
                if !accounts.isEmpty && !isConnected {
                    accountPickerSection
                }
                privacySection
                aboutSection
            }
            .navigationTitle("Settings")
            .alert("Monobank", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var monobankSection: some View {
        Section {
            if isConnected {
                LabeledContent("Account", value: accountLabel.isEmpty ? accountId : accountLabel)
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
                if let syncMessage {
                    Text(syncMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Disconnect", role: .destructive) {
                    disconnect()
                }
            } else {
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
            }
        } header: {
            Text("Monobank")
        } footer: {
            if !isConnected {
                Text("Get a free personal token at api.monobank.ua — log in with the Monobank app, then paste the token here. It is stored only in the device Keychain.")
            }
        }
    }

    private var accountPickerSection: some View {
        Section("Choose the account payments arrive to") {
            ForEach(accounts) { account in
                Button {
                    accountId = account.id
                    accountLabel = account.label
                    accounts = []
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.displayName)
                            Text("\(account.currency) · balance \(Money.format(account.balance, currency: account.currency))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

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
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
        }
    }

    private func connect() async {
        let token = tokenInput.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let info = try await MonobankClient(token: token).clientInfo()
            KeychainStore.save(token, key: KeychainStore.monobankTokenKey)
            accounts = info.accounts
            if accounts.isEmpty {
                errorMessage = "No accounts found for this token."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func disconnect() {
        KeychainStore.delete(key: KeychainStore.monobankTokenKey)
        accountId = ""
        accountLabel = ""
        lastSyncTimestamp = 0
        accounts = []
        tokenInput = ""
    }

    private func syncNow() async {
        guard let token = KeychainStore.load(key: KeychainStore.monobankTokenKey) else {
            errorMessage = "Token missing — reconnect your account."
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let result = try await MonobankSyncService.sync(context: context, token: token, accountId: accountId)
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
