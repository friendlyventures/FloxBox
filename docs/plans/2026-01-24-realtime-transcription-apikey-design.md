# Realtime Transcription API Key UX Design

## Summary
Add a simple API key input row to the PoC UI with a plain-text field and Save button, persisting the key to the macOS Keychain. The key is loaded on launch, can be updated or cleared, and is used by the Realtime client when starting transcription.

## Goals
- Allow entering an OpenAI API key directly in the app.
- Persist the key securely via Keychain.
- Keep UI minimal and fast to test.

## Non-goals
- Password masking or advanced key management.
- Multi-key profiles or per-model keys.
- Sync across devices.

## UX
- Add a top-row section with:
  - TextField (plain text) placeholder: `sk-...`
  - Save button
  - Status label (Saved / Cleared / Error)
- Key loads automatically from Keychain on launch.
- Save updates Keychain; empty value clears Keychain.

## Architecture
- Add `KeychainStoring` protocol and `SystemKeychainStore` implementation in `FloxBoxCore`.
- `TranscriptionViewModel` owns the API key field and uses the keychain store.
- ViewModel exposes a lightweight `APIKeyStatus` for UI feedback.

## Error Handling
- Keychain errors surface as a brief message in the UI.
- If Start is pressed with no API key, show an error and do not connect.

## Testing
- ViewModel tests using an in-memory keychain stub.
- UI build test ensures ContentView still compiles with the new key row.
