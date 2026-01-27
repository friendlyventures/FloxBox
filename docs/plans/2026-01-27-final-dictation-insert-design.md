# Final Dictation Insert (Single-shot) Design

## Goal
- Capture and transcribe audio as usual, but insert text **only once** after the final transcript is complete.
- Preserve the full transcript in memory for a menu bar action: **Paste last transcript**.
- Avoid clipboard usage. Use Accessibility (AX) insertion with a CGEvent fallback.
- Maintain transcript history and debug traces.

## Architecture
- **TranscriptionViewModel** remains the source of truth for transcript state via `TranscriptStore`.
- Introduce a **final-only injection controller** that performs a single insert at the end of dictation.
- Add an insertion pipeline:
  - `AXTextInserter`: finds the focused AX element, reads value + selection, inserts text at caret, updates selection.
  - `CGEventTextInserter`: posts a single Unicode event for the full text (fallback).
- **Menu bar** exposes `Paste last transcript`, always visible and disabled when empty. This calls the same final-only insert path.

## Data Flow
1) **Recording starts**
   - Reset transcript store and start session logging.
   - Begin audio capture + realtime session as today.

2) **While recording**
   - Apply deltas/commits to `TranscriptStore` for history/debug.
   - Do **not** inject into the frontmost app.

3) **Final transcript ready** (realtime completion for awaited item, or REST completion)
   - Update `TranscriptStore` and `transcript` display state.
   - Store `lastFinalTranscript` in memory.
   - Call `dictationInjector.insertFinal(text:)` once.

4) **Manual paste**
   - Menu bar action calls `pasteLastTranscript()` on the view model.
   - This reuses the same `insertFinal(text:)` path.

## Insertion Details
- **Prefix handling** is preserved (space insertion logic) but only applied once at final insert.
- **AX insertion algorithm**:
  - Resolve focused element (reuse focused element discovery from `AXFocusedTextContextProvider`).
  - Read `kAXValueAttribute` and `kAXSelectedTextRangeAttribute`.
  - Build `newValue = prefix + text` inserted at caret.
  - Set `kAXValueAttribute` and update selection to end of inserted text.
  - If any step fails, log the reason and return failure.
- **Fallback**: on AX failure, attempt a single CGEvent Unicode insert.

## Error Handling & Logging
- Log at each stage:
  - `dictation.insert.start len=...`
  - `dictation.insert.ax.success`
  - `dictation.insert.ax.fail reason=...`
  - `dictation.insert.cg.success`
  - `dictation.insert.cg.fail`
- If both AX and CG fail, keep `lastFinalTranscript` and show a toast like:
  - "Unable to insert text. Use Menu Bar → Paste last transcript."

## Menu Bar UI
- Add a menu item **Paste last transcript**.
- Always visible; disabled when `lastFinalTranscript` is nil/empty.

## Testing
- Unit tests for the final-only injector:
  - AX success path inserts once, no CG fallback.
  - AX failure triggers CG fallback.
  - Prefix logic applied once at insert.
- View model tests:
  - No injection on deltas; injection happens on final completion.
  - `lastFinalTranscript` is set on final completion and used by menu bar action.
- Menu bar action:
  - `pasteLastTranscript()` is a no-op when empty.
  - Calls insert when transcript is present.
