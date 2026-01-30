# Transcription Post-Processing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a low-latency post-processing pass that formats final transcripts using a fast OpenAI model, applies a personal glossary, and surfaces formatting status/retry UX without altering meaning.

**Architecture:** Add a persisted FormattingSettings store and PersonalGlossary store, a prompt builder + validator for safe edits, an OpenAI Responses API formatting client with retrying pipeline, then integrate into `TranscriptionViewModel` so formatting runs only after final transcription (realtime or REST). Settings/UI expose model choice + glossary editing and show formatting status.

**Tech Stack:** Swift, SwiftUI, Observation, URLSession, Codable, OpenAI Responses API.

---

### Task 1: Formatting models + settings store

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/FormattingModel.swift`
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/FormattingSettingsStore.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/FormattingSettingsStoreTests.swift`

**Step 1: Write the failing test**

```swift
@testable import FloxBoxCore
import XCTest

final class FormattingSettingsStoreTests: XCTestCase {
    func testDefaultsPersist() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.removePersistentDomain(forName: defaults.domainName)

        let store = FormattingSettingsStore(userDefaults: defaults)

        XCTAssertTrue(store.isEnabled)
        XCTAssertEqual(store.model, .gpt5Nano)

        store.isEnabled = false
        store.model = .gpt5Mini

        let reloaded = FormattingSettingsStore(userDefaults: defaults)
        XCTAssertFalse(reloaded.isEnabled)
        XCTAssertEqual(reloaded.model, .gpt5Mini)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter FormattingSettingsStoreTests` (from `Packages/FloxBoxCore`)
Expected: FAIL with “Use of unresolved identifier 'FormattingSettingsStore'”.

**Step 3: Write minimal implementation**

```swift
import Foundation
import Observation

public enum FormattingModel: String, CaseIterable, Identifiable, Codable {
    case gpt5 = "gpt-5.2"
    case gpt5Mini = "gpt-5-mini"
    case gpt5Nano = "gpt-5-nano"

    public static let defaultModel: FormattingModel = .gpt5Nano

    public var id: String { rawValue }
    public var displayName: String { rawValue }
}

@Observable
public final class FormattingSettingsStore {
    private struct Snapshot: Codable {
        let isEnabled: Bool
        let model: FormattingModel
    }

    public var isEnabled: Bool {
        didSet { persist() }
    }

    public var model: FormattingModel {
        didSet { persist() }
    }

    private let userDefaults: UserDefaults
    private let storageKey = "floxbox.formatting.settings.v1"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(Snapshot.self, from: data)
        {
            isEnabled = decoded.isEnabled
            model = decoded.model
        } else {
            isEnabled = true
            model = .defaultModel
        }
    }

    private func persist() {
        let snapshot = Snapshot(isEnabled: isEnabled, model: model)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter FormattingSettingsStoreTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/FormattingModel.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/FormattingSettingsStore.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/FormattingSettingsStoreTests.swift

git commit -m "feat: add formatting settings store"
```

---

### Task 2: Personal glossary models + store

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/PersonalGlossaryEntry.swift`
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/PersonalGlossaryStore.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/PersonalGlossaryStoreTests.swift`

**Step 1: Write the failing test**

```swift
@testable import FloxBoxCore
import XCTest

final class PersonalGlossaryStoreTests: XCTestCase {
    func testGlossaryPersistsEntries() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.removePersistentDomain(forName: defaults.domainName)

        let store = PersonalGlossaryStore(userDefaults: defaults)
        let entry = PersonalGlossaryEntry(
            id: UUID(),
            term: "OpenAI",
            aliases: ["Open AI", "open ai"],
            notes: "Company name",
            isEnabled: true
        )

        store.entries = [entry]

        let reloaded = PersonalGlossaryStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.term, "OpenAI")
        XCTAssertEqual(reloaded.activeEntries.count, 1)
    }

    func testGlossaryFiltersDisabledEntries() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.removePersistentDomain(forName: defaults.domainName)

        let store = PersonalGlossaryStore(userDefaults: defaults)
        store.entries = [
            PersonalGlossaryEntry(term: "Foo", aliases: [], notes: nil, isEnabled: false),
            PersonalGlossaryEntry(term: "Bar", aliases: [], notes: nil, isEnabled: true),
        ]

        XCTAssertEqual(store.activeEntries.map { $0.term }, ["Bar"])
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter PersonalGlossaryStoreTests`
Expected: FAIL with “Use of unresolved identifier 'PersonalGlossaryStore'”.

**Step 3: Write minimal implementation**

```swift
import Foundation
import Observation

public struct PersonalGlossaryEntry: Codable, Identifiable, Equatable {
    public var id: UUID
    public var term: String
    public var aliases: [String]
    public var notes: String?
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        term: String,
        aliases: [String],
        notes: String?,
        isEnabled: Bool
    ) {
        self.id = id
        self.term = term
        self.aliases = aliases
        self.notes = notes
        self.isEnabled = isEnabled
    }
}

@Observable
public final class PersonalGlossaryStore {
    public var entries: [PersonalGlossaryEntry] {
        didSet { persist() }
    }

    public var activeEntries: [PersonalGlossaryEntry] {
        entries.filter { $0.isEnabled && !$0.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private let userDefaults: UserDefaults
    private let storageKey = "floxbox.glossary.v1"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([PersonalGlossaryEntry].self, from: data)
        {
            entries = decoded
        } else {
            entries = []
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter PersonalGlossaryStoreTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/PersonalGlossaryEntry.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/PersonalGlossaryStore.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/PersonalGlossaryStoreTests.swift

git commit -m "feat: add personal glossary store"
```

---

### Task 3: Formatting prompt builder + validator

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/FormattingPromptBuilder.swift`
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/FormatValidator.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/FormattingPromptBuilderTests.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/FormatValidatorTests.swift`

**Step 1: Write the failing tests**

```swift
@testable import FloxBoxCore
import XCTest

final class FormattingPromptBuilderTests: XCTestCase {
    func testPromptIncludesRulesAndGlossary() {
        let builder = FormattingPromptBuilder()
        let glossary = [
            PersonalGlossaryEntry(term: "OpenAI", aliases: ["Open AI"], notes: nil, isEnabled: true),
        ]

        let prompt = builder.makePrompt(text: "Open AI makes models.", glossary: glossary)

        XCTAssertTrue(prompt.contains("Do not paraphrase"))
        XCTAssertTrue(prompt.contains("OpenAI"))
        XCTAssertTrue(prompt.contains("Open AI"))
        XCTAssertTrue(prompt.contains("Transcript:"))
    }
}

final class FormatValidatorTests: XCTestCase {
    func testValidatorAcceptsMinorFormattingChanges() {
        let validator = FormatValidator()
        XCTAssertTrue(validator.isAcceptable(
            original: "Open AI makes models",
            formatted: "OpenAI makes models."
        ))
    }

    func testValidatorRejectsMajorChanges() {
        let validator = FormatValidator()
        XCTAssertFalse(validator.isAcceptable(
            original: "Open AI makes models",
            formatted: "We should go to the store."
        ))
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter FormattingPromptBuilderTests` and `swift test --filter FormatValidatorTests`
Expected: FAIL with unresolved identifiers.

**Step 3: Write minimal implementation**

```swift
import Foundation

public struct FormattingPromptBuilder {
    public init() {}

    public func makePrompt(text: String, glossary: [PersonalGlossaryEntry]) -> String {
        let glossaryLines = glossary
            .filter { $0.isEnabled }
            .map { entry in
                let aliases = entry.aliases.joined(separator: ", ")
                return "- Preferred: \(entry.term). Variants: \(aliases)"
            }
            .joined(separator: "\n")

        let glossaryBlock = glossaryLines.isEmpty
            ? "(no glossary entries)"
            : glossaryLines

        return """
        You are a transcript post-processor. Return only the corrected transcript.
        Rules:
        - Do not paraphrase, summarize, or change meaning.
        - Preserve words except for obvious transcription corrections.
        - Fix punctuation, casing, spacing, and paragraphing only.
        - Use paragraph breaks for topic shifts, not pauses.
        - Apply glossary: replace variants with the preferred term.
        - Output only the final transcript with no commentary.

        Glossary:
        \(glossaryBlock)

        Transcript:
        \(text)
        """
    }
}

public struct FormatValidator {
    public var minimumSimilarity: Double

    public init(minimumSimilarity: Double = 0.78) {
        self.minimumSimilarity = minimumSimilarity
    }

    public func isAcceptable(original: String, formatted: String) -> Bool {
        let a = normalize(original)
        let b = normalize(formatted)
        guard a.count > 1, b.count > 1 else { return a == b }
        let score = diceCoefficient(a, b)
        return score >= minimumSimilarity
    }

    private func normalize(_ text: String) -> String {
        let scalars = text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private func diceCoefficient(_ a: String, _ b: String) -> Double {
        let aBigrams = bigrams(a)
        let bBigrams = bigrams(b)
        guard !aBigrams.isEmpty, !bBigrams.isEmpty else { return 0 }
        var counts: [String: Int] = [:]
        for gram in aBigrams { counts[gram, default: 0] += 1 }
        var intersection = 0
        for gram in bBigrams {
            if let count = counts[gram], count > 0 {
                intersection += 1
                counts[gram] = count - 1
            }
        }
        return (2.0 * Double(intersection)) / Double(aBigrams.count + bBigrams.count)
    }

    private func bigrams(_ text: String) -> [String] {
        guard text.count >= 2 else { return [] }
        let chars = Array(text)
        return (0..<(chars.count - 1)).map { String([chars[$0], chars[$0 + 1]]) }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter FormattingPromptBuilderTests` and `swift test --filter FormatValidatorTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/FormattingPromptBuilder.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/FormatValidator.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/FormattingPromptBuilderTests.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/FormatValidatorTests.swift

git commit -m "feat: add formatting prompt builder and validator"
```

---

### Task 4: OpenAI formatting client (Responses API)

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/FormattingClient.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/FormattingClientTests.swift`

**Step 1: Write the failing test**

```swift
@testable import FloxBoxCore
import XCTest

final class FormattingClientTests: XCTestCase {
    func testFormattingClientSendsResponsesRequest() async throws {
        let recorder = RequestRecorder()
        let session = URLSession(configuration: recorder.configuration)
        let client = OpenAIFormattingClient(apiKey: "sk-test", session: session)

        _ = try await client.format(
            text: "Hello world",
            model: .gpt5Nano,
            glossary: []
        )

        XCTAssertEqual(recorder.lastRequest?.url?.path, "/v1/responses")
        XCTAssertEqual(recorder.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(recorder.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertTrue(recorder.lastBodyString?.contains("\"model\":\"gpt-5-nano\"") == true)
        XCTAssertTrue(recorder.lastBodyString?.contains("\"input\"") == true)
    }

    func testFormattingClientParsesOutputText() async throws {
        let recorder = RequestRecorder(responseBody: """
        {"output":[{"type":"message","content":[{"type":"output_text","text":"Formatted."}]}]}
        """)
        let session = URLSession(configuration: recorder.configuration)
        let client = OpenAIFormattingClient(apiKey: "sk-test", session: session)

        let text = try await client.format(text: "Raw", model: .gpt5Nano, glossary: [])

        XCTAssertEqual(text, "Formatted.")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter FormattingClientTests`
Expected: FAIL with unresolved identifiers.

**Step 3: Write minimal implementation**

```swift
import Foundation

public protocol FormattingClientProtocol {
    func format(text: String, model: FormattingModel, glossary: [PersonalGlossaryEntry]) async throws -> String
}

public final class OpenAIFormattingClient: FormattingClientProtocol {
    private let apiKey: String
    private let session: URLSession
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    private let promptBuilder: FormattingPromptBuilder

    public init(
        apiKey: String,
        session: URLSession = .shared,
        promptBuilder: FormattingPromptBuilder = FormattingPromptBuilder(),
    ) {
        self.apiKey = apiKey
        self.session = session
        self.promptBuilder = promptBuilder
    }

    public func format(text: String, model: FormattingModel, glossary: [PersonalGlossaryEntry]) async throws -> String {
        let prompt = promptBuilder.makePrompt(text: text, glossary: glossary)
        let payload = ResponseRequest(model: model.rawValue, input: prompt, temperature: 0.1)
        let body = try JSONEncoder().encode(payload)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw FormattingClientError.badResponse
        }
        let decoded = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        let text = decoded.outputText
        guard !text.isEmpty else { throw FormattingClientError.emptyOutput }
        return text
    }
}

private struct ResponseRequest: Encodable {
    let model: String
    let input: String
    let temperature: Double
}

private struct ResponseEnvelope: Decodable {
    let output: [ResponseOutputItem]

    var outputText: String {
        output
            .flatMap { $0.content }
            .filter { $0.type == "output_text" }
            .map { $0.text }
            .joined()
    }
}

private struct ResponseOutputItem: Decodable {
    let type: String
    let content: [ResponseContent]
}

private struct ResponseContent: Decodable {
    let type: String
    let text: String
}

enum FormattingClientError: Error {
    case badResponse
    case emptyOutput
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter FormattingClientTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/FormattingClient.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/FormattingClientTests.swift

git commit -m "feat: add OpenAI formatting client"
```

---

### Task 5: Formatting pipeline with retries

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/FormattingPipeline.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TestDoubles.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/FormattingPipelineTests.swift`

**Step 1: Write the failing test**

```swift
@testable import FloxBoxCore
import XCTest

final class FormattingPipelineTests: XCTestCase {
    func testPipelineRetriesOnFailure() async {
        let client = TestFormattingClient(results: [.failure, .success("Done")])
        let pipeline = FormattingPipeline(client: client, validator: FormatValidator(), maxAttempts: 2)

        let result = try? await pipeline.format(text: "Hi", model: .gpt5Nano, glossary: [])

        XCTAssertEqual(result, "Done")
        XCTAssertEqual(client.callCount, 2)
    }

    func testPipelineFailsWhenValidationRejects() async {
        let client = TestFormattingClient(results: [.success("Bad")])
        let validator = FormatValidator(minimumSimilarity: 0.99)
        let pipeline = FormattingPipeline(client: client, validator: validator, maxAttempts: 1)

        do {
            _ = try await pipeline.format(text: "Good", model: .gpt5Nano, glossary: [])
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(client.callCount, 1)
        }
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter FormattingPipelineTests`
Expected: FAIL with unresolved identifiers.

**Step 3: Write minimal implementation**

```swift
import Foundation

public final class FormattingPipeline {
    private let client: FormattingClientProtocol
    private let validator: FormatValidator
    private let maxAttempts: Int
    private let retryDelayNanos: UInt64

    public init(
        client: FormattingClientProtocol,
        validator: FormatValidator = FormatValidator(),
        maxAttempts: Int = 2,
        retryDelayNanos: UInt64 = 300_000_000,
    ) {
        self.client = client
        self.validator = validator
        self.maxAttempts = max(1, maxAttempts)
        self.retryDelayNanos = retryDelayNanos
    }

    public func format(
        text: String,
        model: FormattingModel,
        glossary: [PersonalGlossaryEntry],
    ) async throws -> String {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                let formatted = try await client.format(text: text, model: model, glossary: glossary)
                guard validator.isAcceptable(original: text, formatted: formatted) else {
                    throw FormattingPipelineError.validationFailed
                }
                return formatted
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: retryDelayNanos)
                }
            }
        }
        throw lastError ?? FormattingPipelineError.unknown
    }
}

enum FormattingPipelineError: Error {
    case validationFailed
    case unknown
}
```

**Step 4: Update test doubles**

```swift
final class TestFormattingClient: FormattingClientProtocol {
    enum Result {
        case success(String)
        case failure
    }

    private var results: [Result]
    private(set) var callCount = 0

    init(results: [Result]) {
        self.results = results
    }

    func format(text _: String, model _: FormattingModel, glossary _: [PersonalGlossaryEntry]) async throws -> String {
        callCount += 1
        guard !results.isEmpty else { return "" }
        switch results.removeFirst() {
        case let .success(value):
            return value
        case .failure:
            throw FormattingPipelineError.unknown
        }
    }
}
```

**Step 5: Run test to verify it passes**

Run: `swift test --filter FormattingPipelineTests`
Expected: PASS

**Step 6: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/FormattingPipeline.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/FormattingPipelineTests.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TestDoubles.swift

git commit -m "feat: add formatting pipeline with retry"
```

---

### Task 6: Integrate formatting into view model + UI

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/App/FloxBoxAppModel.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/App/MenubarMenu.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Views/SettingsView.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Views/DebugPanelView.swift`
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Views/Settings/GlossaryEditorView.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/TranscriptionViewModelTests.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/SettingsViewTests.swift`

**Step 1: Write the failing test**

```swift
@MainActor
final class FormattingIntegrationTests: XCTestCase {
    func testStopFormatsTranscriptBeforeInsert() async {
        let realtime = TestRealtimeClient()
        let audio = TestAudioCapture()
        let toast = TestToastPresenter()
        let injector = TestDictationInjector()
        let keychain = InMemoryKeychainStore()
        let settings = FormattingSettingsStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let glossary = PersonalGlossaryStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let client = TestFormattingClient(results: [.success("Formatted text")])

        let viewModel = TranscriptionViewModel(
            keychain: keychain,
            audioCapture: audio,
            realtimeFactory: { _ in realtime },
            permissionRequester: { true },
            notchOverlay: TestNotchOverlay(),
            pttTailNanos: 0,
            accessibilityChecker: { true },
            secureInputChecker: { false },
            permissionsPresenter: {},
            dictationInjector: injector,
            toastPresenter: toast,
            formattingSettings: settings,
            glossaryStore: glossary,
            formattingClientFactory: { _ in client }
        )

        viewModel.apiKeyInput = "sk-test"
        await viewModel.startAndWait()
        audio.emit(Data([0x01]))

        await viewModel.stopAndWait()
        realtime.emit(.inputAudioCommitted(.init(itemId: "item1", previousItemId: nil)))
        realtime.emit(.transcriptionCompleted(.init(itemId: "item1", contentIndex: 0, transcript: "Raw text")))
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(injector.insertedTexts.last, "Formatted text")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter FormattingIntegrationTests`
Expected: FAIL due to missing formatting injection.

**Step 3: Update `TranscriptionViewModel` to post-process on completion**

- Add properties:
  - `formattingSettings: FormattingSettingsStore`
  - `glossaryStore: PersonalGlossaryStore`
  - `formattingClientFactory: (String) -> FormattingClientProtocol`
  - `formattingStatus: FormattingStatus` (new enum)
  - `lastRawTranscript: String?`
- Add helper `finalizeTranscript(rawText:)` which:
  - stores `lastRawTranscript`
  - if formatting enabled + apiKey present: shows toast "Polishing transcript…", runs pipeline, updates `lastFinalTranscript` + `transcript`, inserts final text, then calls `finalizeDictationInjectionIfNeeded()`
  - if formatting disabled: insert raw text immediately
  - on error: show toast + action “Paste raw transcript”, mark status failed, still call `finalizeDictationInjectionIfNeeded()`
- Ensure `handleTranscriptionCompleted` and `applyRestTranscription` call `finalizeTranscript(rawText:)` instead of `insertFinalTranscriptIfNeeded()`.

**Step 4: Wire settings + glossary into app model**

- Add `formattingSettings` + `glossaryStore` properties in `FloxBoxAppModel`.
- Pass them into `TranscriptionViewModel` initializer.

**Step 5: Add glossary editor UI + formatting settings UI**

- `GlossaryEditorView` with list of entries (term, aliases, notes, enabled toggle) and add/delete.
- `SettingsView` adds formatting toggle + model picker + glossary editor.
- `DebugPanelView` adds read-only formatting status row.
- Update menu to allow paste raw transcript when formatting failed (optional conditional row).

**Step 6: Run tests to verify they pass**

Run: `swift test --filter FormattingIntegrationTests` and `swift test --filter SettingsViewTests`
Expected: PASS

**Step 7: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/App/FloxBoxAppModel.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/App/MenubarMenu.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Views/SettingsView.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Views/DebugPanelView.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Views/Settings/GlossaryEditorView.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/TranscriptionViewModelTests.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/SettingsViewTests.swift

git commit -m "feat: format transcripts after completion"
```
