# Shortcut Permissions and Defaults Design

**Goal:** Default push-to-talk to right command and ensure Input Monitoring permissions are requested and rechecked without app restart.

## Approach

- Seed a default push-to-talk shortcut (right command only) when no persisted shortcuts exist.
- Use CoreGraphics listen-event access APIs to preflight and request Input Monitoring before creating the event tap.
- Keep retrying tap creation while permissions are missing; clear status once granted.

## User Experience

- macOS shows the Input Monitoring prompt when permission is missing.
- If the user grants permission while the app is running, the event tap starts automatically without a restart.
