# TherapyLedger

A private, on-device iOS app for psychotherapists to track sessions, payments, and patient balances.

## Features

- **Internal calendar** — recurring weekly slots per patient, materialized into individual sessions you can complete, mark as missed, reschedule (with history), or cancel.
- **Payments** — synced from your personal Monobank account (free official API) or entered manually; payers are linked to patients once and matched automatically afterwards.
- **Balances & reports** — per-patient debt (billed vs. received), monthly and yearly totals.
- **Privacy-first** — all data stays on the device (SwiftData). The Monobank token is stored in the Keychain. No backend.

## Stack

- iOS 26, SwiftUI, SwiftData
- Swift 6 (MainActor-by-default isolation, approachable concurrency)
- Swift Testing for unit tests

## Monobank setup

1. Get a personal token at <https://api.monobank.ua/> (log in with the app).
2. Open **Settings → Monobank**, paste the token, choose the account payments arrive to.
3. Sync pulls incoming transfers for the last 31 days; the sender name/IBAN is matched against payer aliases you confirm once per payer.

The personal Monobank API is for personal use only and is rate-limited to 1 request per 60 seconds per endpoint.
