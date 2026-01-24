# Realtime Transcription API Key Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an API key input UI that saves to Keychain and uses the stored key to start transcription.

**Architecture:** Introduce a `KeychainStoring` protocol with a `SystemKeychainStore` implementation. The `TranscriptionViewModel` owns the API key field and status and uses the keychain store to load/save keys. The SwiftUI view binds to those properties and exposes a Save button with status feedback.

**Tech Stack:** Swift 6.2, SwiftUI, Keychain Services (Security), Swift Package Manager.

**Skills:** Follow @superpowers:test-driven-development for testable units and @superpowers:systematic-debugging if any test fails.

### Task 1: Add Keychain store abstraction

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Keychain/KeychainStore.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/KeychainStoreTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import FloxBoxCore

final class KeychainStoreTests: XCTestCase {
    func testInMemoryKeychainStoresValues() {
        let store = InMemoryKeychainStore()
        XCTAssertNil(try? store.load())

        XCTAssertNoThrow(try store.save("sk-test"))
        XCTAssertEqual(try store.load(), "sk-test")

        XCTAssertNoThrow(try store.delete())
        XCTAssertNil(try store.load())
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter KeychainStoreTests`
Expected: FAIL with missing types.

**Step 3: Write minimal implementation**

`Packages/FloxBoxCore/Sources/FloxBoxCore/Keychain/KeychainStore.swift`:

```swift
import Foundation
import Security

public protocol KeychainStoring {
    func load() throws -> String?
    func save(_ value: String) throws
    func delete() throws
}

public enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}

public struct SystemKeychainStore: KeychainStoring {
    private let service: String
    private let account: String

    public init(
        service: String = Bundle.main.bundleIdentifier ?? "FloxBox",
        account: String = "openai-api-key"
    ) {
        self.service = service
        self.account = account
    }

    public func load() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound {
            return
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
```

`Packages/FloxBoxCore/Tests/FloxBoxCoreTests/KeychainStoreTests.swift`:

```swift
import XCTest
@testable import FloxBoxCore

final class InMemoryKeychainStore: KeychainStoring {
    private var value: String?

    func load() throws -> String? {
        value
    }

    func save(_ value: String) throws {
        self.value = value
    }

    func delete() throws {
        value = nil
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore --filter KeychainStoreTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Keychain/KeychainStore.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/KeychainStoreTests.swift
git commit -m "feat: add keychain store abstraction"
```

### Task 2: Update transcription view model for API key management

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/TranscriptionViewModelTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import FloxBoxCore

@MainActor
final class TranscriptionViewModelTests: XCTestCase {
    func testLoadsAPIKeyFromKeychain() {
        let keychain = InMemoryKeychainStore()
        try? keychain.save("sk-test")
        let viewModel = TranscriptionViewModel(keychain: keychain)

        XCTAssertEqual(viewModel.apiKeyInput, "sk-test")
    }

    func testSaveClearsKeychainWhenEmpty() {
        let keychain = InMemoryKeychainStore()
        let viewModel = TranscriptionViewModel(keychain: keychain)

        viewModel.apiKeyInput = ""
        viewModel.saveAPIKey()

        XCTAssertNil(try? keychain.load())
        XCTAssertEqual(viewModel.apiKeyStatus, .cleared)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter TranscriptionViewModelTests`
Expected: FAIL with missing properties/initializer.

**Step 3: Write minimal implementation**

Update `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift`:

```swift
public enum APIKeyStatus: Equatable {
    case idle
    case saved
    case cleared
    case error(String)

    public var message: String? {
        switch self {
        case .idle:
            return nil
        case .saved:
            return "Saved"
        case .cleared:
            return "Cleared"
        case .error(let message):
            return message
        }
    }
}
```

Add to `TranscriptionViewModel`:
- `public var apiKeyInput: String`
- `public var apiKeyStatus: APIKeyStatus`
- Inject `keychain: any KeychainStoring` in init (default `SystemKeychainStore()`)
- Load stored key in init and assign to `apiKeyInput`.
- Add `saveAPIKey()` to save or delete key, updating `apiKeyStatus`.
- Replace env var lookup with `apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)`.

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore --filter TranscriptionViewModelTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/TranscriptionViewModelTests.swift
git commit -m "feat: add API key handling to view model"
```

### Task 3: Update SwiftUI view to include API key UI

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Views/ContentView.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/ContentViewTests.swift`

**Step 1: Write the failing test**

```swift
import SwiftUI
import XCTest
@testable import FloxBoxCore

@MainActor
final class ContentViewTests: XCTestCase {
    func testContentViewBuildsWithAPIKeyRow() {
        _ = ContentView(configuration: .appStore)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter ContentViewTests`
Expected: FAIL with missing API key UI types.

**Step 3: Write minimal implementation**

Update `Packages/FloxBoxCore/Sources/FloxBoxCore/Views/ContentView.swift` to add:
- A `TextField("sk-...", text: $viewModel.apiKeyInput)` in a top-row HStack.
- A Save button calling `viewModel.saveAPIKey()`.
- A status label showing `viewModel.apiKeyStatus.message` (if non-nil).

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore --filter ContentViewTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Views/ContentView.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/ContentViewTests.swift
git commit -m "feat: add API key input to UI"
```
