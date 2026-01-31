# Laptop-Open Built-in Mic Preference Design

**Goal:** When the user has not explicitly chosen a mic ("System Default"), prefer the built-in microphone **only** when a laptop is open, without changing the macOS system default device.

**Non-Goals:**
- Do not change the system-wide default input device.
- Do not override an explicit user-selected mic.
- Do not add new UI unless needed for debugging.

## Architecture

Add a lightweight display-state probe and an audio-device selector:

- **Laptop open detection (heuristic):**
  - Use CoreGraphics display APIs to check for an **active built-in display**.
  - If any active display is built-in, treat as "laptop open". If no built-in active displays, treat as clamshell/desktop.

- **Built-in mic selection:**
  - Enumerate input devices and pick the first device with built-in transport type.
  - Fall back to name/UID heuristics (e.g., "Built-in Microphone") if transport type is unavailable.

- **Effective input selection (per session only):**
  - If `selectedInputDeviceID` is set, use it.
  - Else, if laptop open and built-in mic available, use built-in mic.
  - Else, use nil (system default).

This uses the existing `AudioCapture.setPreferredInputDevice(...)` call (AUHAL current device) and affects only FloxBox's capture.

## Implementation Plan (High-Level)

1. **Display state helper**
   - Add a helper (e.g., `LaptopDisplayState.isLaptopOpen()`) using CoreGraphics display list + `CGDisplayIsBuiltin` + `CGDisplayIsActive`.

2. **Built-in mic detection**
   - Extend `AudioInputDeviceProvider` with `builtInInputDeviceID()`.
   - Use CoreAudio `kAudioDevicePropertyTransportType` and a name/UID fallback.

3. **Effective device selection**
   - In `TranscriptionViewModel`, compute `effectiveInputDeviceID` before `audioCapture.setPreferredInputDevice(...)`.
   - Keep `selectedInputDeviceID` unchanged so the UI still shows "System Default".

## Error Handling

- If built-in detection fails or is unavailable, fall back to system default (nil).
- If device selection fails at `AudioCapture.start`, the existing error path applies.

## Testing

- Unit test the selection logic with injected providers:
  - User-selected device wins.
  - Laptop open + built-in available chooses built-in.
  - Laptop open + built-in missing falls back to nil.
  - Laptop closed always uses nil (if no user selection).

## Rollout

- Default to this behavior in direct/Xcode builds; it should be safe for all distributions because it does not alter system defaults.
