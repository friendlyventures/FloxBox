# Notch Recording UI (PoC)

## Goals
- Show a **minimal black recording UI** that appears to grow out of the MacBook notch.
- Animate **in on recording start** and **out on stop** (no auto‑hide).
- Keep the UI **simple**: indicator + short label/timer (no waveform yet).
- Support **notched Macs** and a **graceful fallback** on non‑notch screens.
- Use **SPM dependencies** where possible to avoid reinventing the windowing logic.

## Non-goals
- No waveform/level meter yet (we will add later).
- No inline transcript text.
- No interactivity beyond visual indicator (no buttons in the notch UI).
- No App Store distribution considerations.

## Prior Art (Inspiration Only)
- **Atoll** and **Boring.Notch** provide the best reference for notch alignment and animation feel. Both are GPL; we will **not reuse their code**, only the interaction patterns.

## Dependency Strategy
- Use **DynamicNotchKit** via SPM for notch window placement/management.
- If DynamicNotchKit proves insufficient, fall back to a lightweight **NSPanel** overlay implementation, still driven by SwiftUI.

## UI/UX Design
- **Closed state**: matches the physical notch width/height; fully black, no content.
- **Open state**: expands **to the left** from the notch by a fixed width (e.g., 180–240px), keeping the right edge aligned to the notch.
- **Content** (minimal):
  - Red dot (pulsing) + “REC” label.
  - Optional elapsed time (mm:ss).
- **Animation**:
  - `spring`/`snappy` expand on start (fast, slightly elastic).
  - Smooth shrink on stop, then hide after animation completes.
  - Subtle blinking dot using `TimelineView(.animation)`.

## Behavior
- **Start recording** → show notch UI and animate open.
- **Stop recording** → animate closed, then hide.
- **No VAD coupling**: only explicit Start/Stop triggers animations.

## Technical Notes
- Detect notched screens via `NSScreen.safeAreaInsets.top > 0`.
- Use **notch width** if available via auxiliary top inset APIs; otherwise fall back to a tuned default width.
- Present on the **screen with active window** (or main screen), with future expansion to multi‑screen if needed.
- Window level: prefer `statusBar` / `floating` for visibility while minimizing interference.

## Risks / Edge Cases
- Full‑screen apps or display changes could move/clip the notch UI; we’ll listen for `NSWorkspace.screensDidWakeNotification` and `NSApplication.didChangeScreenParametersNotification`.
- Fallback experience on non‑notch Macs should still feel polished (center‑top pill).

## Next Steps (Implementation)
- Add `NotchRecordingController` to manage visibility + animation state.
- Implement `NotchRecordingView` (SwiftUI) with minimal visual components.
- Integrate DynamicNotchKit and wire to recording lifecycle.
- Add non‑notch fallback overlay.
