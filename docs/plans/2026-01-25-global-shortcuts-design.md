# Global Shortcuts (Left/Right Modifiers) Design

**Goal:** Add precise global shortcuts for direct distribution (left/right modifiers + modifier-only), while preparing an App Store-safe fallback that supports traditional global hotkeys.

**Architecture:** Introduce a shortcuts subsystem in `Packages/FloxBoxCore` with a shared model (`ShortcutDefinition`) and a pluggable backend (`ShortcutBackend`). Direct builds use a CGEventTap backend for precision; App Store builds use a Carbon-based backend with reduced feature set. A `ShortcutCoordinator` wires persistence to backend registration and emits shortcut triggers to the app.

**Tech Stack:** Swift 6.2+, SwiftUI, Observation (`@Observable`), CGEventTap (direct builds), Carbon hotkey library (App Store builds).

## Constraints
- Direct distribution must support left/right modifier distinction and modifier-only shortcuts (e.g., Right Command).
- App Store distribution must avoid low-level input monitoring if it risks review; global hotkeys must still work but can ignore left/right and modifier-only.
- Push-to-talk behavior: press starts recording, release stops.

## Core Types
- `ShortcutDefinition`:
  - `id`, `name`
  - `keyCode: UInt16?` (nil for modifier-only shortcuts)
  - `modifiers: ModifierSet` (left/right aware)
  - `behavior: ShortcutBehavior` (`.pushToTalk`, `.toggle`)
- `ModifierSet`: bitset or struct with explicit left/right flags.
- `ShortcutStore` (`@Observable`): persists array of `ShortcutDefinition` in `UserDefaults`, validates, publishes changes.

## Backends
- `ShortcutBackend` protocol: `start()`, `stop()`, `register(_:)`, `unregister(_:)`, `onTrigger` callback.
- **EventTapShortcutBackend (Direct):**
  - Uses CGEventTap to capture `keyDown`, `keyUp`, `flagsChanged`.
  - Maintains `ChordState` for matching `ShortcutDefinition`.
  - Supports modifier-only and left/right precision.
- **CarbonShortcutBackend (App Store):**
  - Wraps a Carbon-based hotkey library.
  - Drops left/right distinction and rejects modifier-only shortcuts.
  - Coerces `.pushToTalk` to `.toggle` with UI warning.

## Recording UI (ContentView for POC)
- `ShortcutRecorderView` in `ContentView` (quick integration).
- Direct build recorder listens to event tap for accurate capture.
- App Store build recorder uses Carbon library recorder or a simplified key capture.
- Inline validation/error messaging when a shortcut is unsupported.

## Push-to-Talk Behavior
- **Non-modifier shortcut:** start on first chord-complete `keyDown` (ignore repeats), stop on primary key `keyUp`.
- **Modifier-only shortcut:** start when required modifiers become active; stop when any required modifier is released.
- Track `isRecordingTriggeredByShortcut` to avoid conflicts with manual UI toggles.

## Permissions & Error Handling
- Direct build shows guidance when Input Monitoring/Accessibility permission is missing.
- If event tap is disabled, backend attempts limited re-enable, otherwise enters paused state with UI notice.
- App Store build never requests input monitoring; it rejects unsupported shortcuts with a clear explanation.

## Testing
- Unit tests for `ShortcutDefinition` encoding/decoding, modifier normalization, and chord matching logic.
- Manual QA checklist:
  - Right Command alone
  - Left Command + Left Option
  - Left Option + Space
  - Permission missing → UI warning and no trigger
  - App Store backend rejects modifier-only shortcuts

## App Store Considerations
- Global shortcuts are supported in App Store build but without left/right or modifier-only precision.
- UI will communicate feature differences between direct and App Store builds.
