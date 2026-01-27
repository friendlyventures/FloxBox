# Permissions Interstitial and Network Notch Design

Date: 2026-01-27

## Overview
Improve the permissions interstitial so users can grant all required permissions up front, with explicit per-permission requests and direct links to System Settings. Add a robust network-loading state to the notch UI with timed spinner, cancellation, and clear timeout/retry behavior.

## Goals
- Present a single consolidated permissions interstitial that explains why each permission is needed.
- Trigger system permission prompts only when the user clicks the corresponding button.
- Open System Settings to the relevant Privacy & Security pane after each request.
- Keep the interstitial window at a normal level (not always-on-top) so system prompts are visible.
- Keep the notch visible while network requests are active and surface a delayed spinner.
- Provide a hover-to-cancel affordance that aborts pending requests and returns to idle.
- On final failure, return to idle and notify the user to check network connectivity.

## Non-Goals
- New permissions beyond Input Monitoring, Accessibility, and Microphone.
- A step-by-step wizard flow that blocks the user until every permission is granted.
- Manual retry action in the notch after final failure.

## Permissions Interstitial

### Triggering
- Show on app launch if any required permission is missing.
- Also accessible from onboarding and a menubar item (e.g., "Permissions...").

### Layout
- Single window listing three rows: Input Monitoring, Accessibility, Microphone.
- Each row includes:
  - A short rationale (why it is needed).
  - A status badge (Granted / Not Granted).
  - A "Request" button.

### Behavior
- No auto-prompt on launch. The user must click the specific "Request" button to trigger the prompt.
- After clicking:
  - Request the permission via its native API.
  - Open System Settings to the relevant Privacy & Security pane (best-effort deep link).
  - If the deep link fails, fall back to opening Privacy & Security root.
- Status badges update live by rechecking permission state when the app becomes active and after returning from Settings.
- When all three are granted, the interstitial can auto-dismiss (or show a "Continue" button if we prefer explicit closure).

### Permission APIs (macOS 14.6+)
- Input Monitoring: CoreGraphics listen-event preflight/request API, then open Privacy & Security → Input Monitoring.
- Accessibility: `AXIsProcessTrustedWithOptions` with prompt, then open Privacy & Security → Accessibility.
- Microphone: `AVCaptureDevice.requestAccess(for: .audio)` (or current capture request path), then open Privacy & Security → Microphone.

## Notch + Network State

### States
- Idle → Recording → AwaitingNetwork → Idle
- AwaitingNetwork covers realtime completion wait and REST fallback attempts.

### Spinner + Visibility
- Keep the notch visible for the entire AwaitingNetwork period.
- If AwaitingNetwork lasts longer than 2 seconds, show a spinner in the right notch.
- If the network finishes before 2 seconds, the spinner never appears.

### Ignore Re-press
- If the user presses PTT during AwaitingNetwork, ignore the press (no new session starts).

### Cancellation
- Hovering the spinner morphs it into a cancel icon (SF Symbol: `xmark.circle.fill`).
- Clicking cancel:
  - Cancels any in-flight socket/REST request.
  - Skips any queued retries.
  - Clears pending transcript state.
  - Animates the notch closed and returns to Idle.

### Timeout / Retry Policy
- Realtime completion wait: 5 seconds.
- If realtime fails or times out: REST attempt #1 with a 5-second timeout.
- On failure: wait 2 seconds, then REST attempt #2 with a 5-second timeout.
- If attempt #2 fails: return to Idle and post a system notification: "Dictation failed — check your network".

## Testing / QA
- Interstitial appears on launch when any permission is missing.
- Prompts only fire on button clicks.
- Settings deep links open the expected pane or fall back gracefully.
- Status badges refresh after returning from Settings.
- Spinner appears at 2 seconds, not before.
- Cancel stops all network activity and returns to Idle.
- Final failure triggers a system notification and the notch closes.
