import SwiftUI

/// Pushed screen for choosing (and re-choosing) the Monobank card payments
/// arrive to. Selecting does not pop the screen, so the current choice stays
/// visible and the Back button always works.
struct AccountPickerView: View {
    @AppStorage("monobank.accountId") private var accountId = ""
    @AppStorage("monobank.accountLabel") private var accountLabel = ""
    @State private var accounts: [MonoAccount]
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(initialAccounts: [MonoAccount] = []) {
        _accounts = State(initialValue: initialAccounts)
    }

    var body: some View {
        List {
            Section {
                ForEach(accounts) { account in
                    Button {
                        accountId = account.id
                        accountLabel = account.label
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.displayName)
                                Text("\(account.currency) · balance \(Money.format(account.balance, currency: account.currency))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if account.id == accountId {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Cards and accounts")
            } footer: {
                Text("Synced payments are tagged with the selected card, so each card's incoming transfers stay distinguishable. Pull down to refresh the list (Monobank allows one refresh per minute).")
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .overlay {
            if isLoading && accounts.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if accounts.isEmpty {
                await load()
            }
        }
        .refreshable {
            await load()
        }
    }

    private func load() async {
        guard let token = KeychainStore.load(key: KeychainStore.monobankTokenKey) else {
            errorMessage = "Token missing — connect your Monobank account first."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            accounts = try await MonobankClient(token: token).clientInfo().accounts
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
