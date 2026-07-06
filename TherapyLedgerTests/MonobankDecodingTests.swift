import Foundation
import Testing
@testable import TherapyLedger

struct MonobankDecodingTests {
    @Test func decodesClientInfo() throws {
        let json = """
        {
          "clientId": "3MSaMMtczs",
          "name": "Мазепа Іван",
          "webHookUrl": "",
          "permissions": "psf",
          "accounts": [
            {
              "id": "kKGVoZuHWzqVoZuH",
              "sendId": "uHWzqVoZuH",
              "balance": 10000000,
              "creditLimit": 10000000,
              "type": "black",
              "currencyCode": 980,
              "cashbackType": "UAH",
              "maskedPan": ["537541******1234"],
              "iban": "UA733220010000026201234567890"
            }
          ]
        }
        """
        let info = try JSONDecoder().decode(MonoClientInfo.self, from: Data(json.utf8))
        #expect(info.name == "Мазепа Іван")
        #expect(info.accounts.count == 1)
        let account = try #require(info.accounts.first)
        #expect(account.currency == "UAH")
        #expect(account.displayName == "537541******1234")
    }

    @Test func decodesStatementItems() throws {
        let json = """
        [
          {
            "id": "ZuHWzqkKGVo=",
            "time": 1751630400,
            "description": "Від: Іван Петренко",
            "mcc": 4829,
            "originalMcc": 4829,
            "hold": false,
            "amount": 120000,
            "operationAmount": 120000,
            "currencyCode": 980,
            "commissionRate": 0,
            "cashbackAmount": 0,
            "balance": 1250000,
            "comment": "За сеанс",
            "receiptId": "XXXX-XXXX-XXXX-XXXX"
          },
          {
            "id": "AbCdEfGh123=",
            "time": 1751544000,
            "description": "Кава",
            "mcc": 5814,
            "hold": false,
            "amount": -8500,
            "operationAmount": -8500,
            "currencyCode": 980,
            "balance": 1130000
          }
        ]
        """
        let items = try JSONDecoder().decode([MonoStatementItem].self, from: Data(json.utf8))
        #expect(items.count == 2)
        #expect(items[0].isIncoming)
        #expect(!items[1].isIncoming)
        #expect(items[0].comment == "За сеанс")
        #expect(items[0].date == Date(timeIntervalSince1970: 1_751_630_400))
    }

    @Test func mapsNumericCurrencyCodes() {
        #expect(CurrencyCodeMap.iso(980) == "UAH")
        #expect(CurrencyCodeMap.iso(840) == "USD")
        #expect(CurrencyCodeMap.iso(978) == "EUR")
    }

    @Test func extractsSenderFromDescription() {
        #expect(MonobankSyncService.senderFromDescription("Від: Марія Коваль") == "Марія Коваль")
        #expect(MonobankSyncService.senderFromDescription("From: John") == "John")
        #expect(MonobankSyncService.senderFromDescription("Поповнення") == "Поповнення")
        #expect(MonobankSyncService.senderFromDescription(nil) == nil)
    }
}
