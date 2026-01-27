# Dictation Peek-and-Space Design

Date: 2026-01-27

## Overview
Add a lightweight “peek-and-space” heuristic to reduce word-joining when dictation is inserted into external text fields. The feature uses Accessibility (AX) to inspect the focused text field at the start of a dictation session, and conditionally inserts a single leading space into injected text.

## Goals
- Insert a single leading space when the caret is immediately after a non-whitespace character and the dictated text does not start with whitespace.
- Apply the space once per dictation session (not per partial update).
- Fail safe: if AX data is unavailable or secure input is active, do nothing and preserve current behavior.

## Non-Goals
- Trailing-space insertion.
- Content edits based on the character after the caret.
- Per-update spacing decisions.

## Heuristic (Rule A)
If all conditions are true, prepend a single space to injected text:
- Focused element’s preceding character is non-whitespace.
- Dictated text does not start with whitespace or newline.

Otherwise, no prefix is added.

## Accessibility Context Provider
Create a small provider that returns `{ value: String, caretIndex: Int }` or `nil`:
1. `AXUIElementCreateSystemWide()` → `kAXFocusedUIElementAttribute`.
2. Optionally check role/subrole for secure fields; if secure, return `nil`.
3. `kAXValueAttribute` for current string value.
4. `kAXSelectedTextRangeAttribute` → caret index (use selection start).

If any step fails, return `nil`.

## Injection Integration
- Compute the session prefix once at session start (or first apply).
- Store `sessionPrefix` inside the injection controller.
- Use `sessionPrefix + text` for diffing so the prefix is injected once and tracked in `lastInjected`.
- Do not mutate the transcript itself.

## Error Handling & Permissions
- If Accessibility is not granted or secure input is active, skip the prefix.
- No additional UI prompts or permissions beyond existing Accessibility checks.

## Testing
- Unit tests for the spacing heuristic (various preceding chars, whitespace, caret at start).
- Unit tests confirming prefix inserted once across partial updates.
- AX provider tested with mocked responses (no UI automation required).

## Rollout
Ship behind the current injection path with conservative defaults (prefix only). Monitor logs for false positives.
