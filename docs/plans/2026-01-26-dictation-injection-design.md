# Follow-Focus Dictation Injection Design

**Goal:** Stream realtime dictation directly into the currently focused text field of any app using keyboard event injection, with a permissions-first UX and a clipboard fallback when insertion fails.

## Scope

- macOS 14.6+ direct distribution (no App Store sandbox constraints).
- Follow-focus behavior: typed text always goes to the currently active app/field.
- External apps only: remove the in-app transcript TextEditor used for the PoC.

## Non-goals

- App Store distribution.
- Pinning dictation to a non-focused app or text field.
- Full-featured IME/input-method mode.

## Architecture

- **DictationInjectionController (new, FloxBoxCore):**
  - Maintains `lastInjected` for the active dictation session.
  - Receives live session text from `TranscriptionViewModel` and injects changes.
  - Coalesces rapid updates (short timer) and flushes on stop/completed events.
- **PermissionsWindow (new, app target):**
  - Separate, closable, always-on-top window that lists required permissions.
  - Shows status for Accessibility and provides a "Request Access" button.
  - Auto-dismisses once all required permissions are granted.
- **Toast/Overlay:**
  - Used for permission-required messages, secure-input blocks, and clipboard fallback.

## Data Flow

1. App launch: preflight Accessibility trust. If missing, show PermissionsWindow.
2. User taps Record:
   - If Accessibility missing: show toast and bring PermissionsWindow forward; do not enter recording.
   - If secure input active: show toast and do not enter recording.
   - Otherwise: start dictation session and initialize `lastInjected = ""`.
3. Realtime transcription updates arrive:
   - Compute LCP between `lastInjected` and `nextInjected`.
   - Emit backspaces for deleted chars, then emit Unicode key events for inserted suffix.
   - Post events into the system event stream so the active app receives them.
4. On stop/completed:
   - Flush pending injection, reset `lastInjected`.

## Injection Algorithm

- Compute `commonPrefix = LCP(lastInjected, nextInjected)`.
- `deleteCount = lastInjected.count - commonPrefix.count`.
- `insertText = nextInjected.dropFirst(commonPrefix.count)`.
- Emit `deleteCount` backspace key down/up events.
- Emit a key event with Unicode payload for `insertText`.
- Coalesce updates to avoid flooding while preserving fast live feedback.

## Permissions UX

- **Required:** Accessibility only (for now).
- On first launch and whenever trust is missing, show the PermissionsWindow.
- The "Request Access" button calls `AXIsProcessTrustedWithOptions` with prompt.
- If the user closes the window, it reappears on next record attempt when missing.
- Window stays floating but is closable to avoid overly annoying UX.

## Error Handling & Fallbacks

- If injection fails (event rejected, unexpected errors):
  - Copy full session text to clipboard.
  - Show toast: "Couldn't insert text. Paste with Cmd+V."
- If FloxBox is frontmost: suppress injection by default (external apps only).
- Secure input active: block recording and show toast.

## UI Changes

- Remove the transcript TextEditor from the main window.
- Keep existing controls and status line; external apps are the destination.
- PermissionsWindow is a separate top-level window with clear guidance and a request button.

## Testing

- Unit tests for the injection diff engine (LCP, backspace count, insert suffix).
- Unit tests for recording gate logic (missing Accessibility blocks recording).
- Manual QA:
  - Permission flow (missing -> prompt -> grant -> window auto-dismiss).
  - Follow-focus typing across app switches mid-dictation.
  - Secure input: recording blocked with toast.
  - Injection failure: clipboard fallback + toast.
