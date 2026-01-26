# PTT Instant Record + Async Realtime Connect Design

## Goal
Make push-to-talk feel instant by starting audio capture immediately on key-down, while connecting to realtime in the background. If realtime isn’t ready within 5 seconds or fails, continue recording locally and transcribe via REST on release.

## Context
Current flow waits for websocket connect + session update before starting `AudioCapture`, causing perceivable latency. We already capture a WAV for REST fallback and have retry UI.

## Proposed Behavior
- **Immediate capture:** start `AudioCapture` instantly on PTT press.
- **Async realtime:** connect and send session update in parallel.
- **Preconnect buffer:** while realtime isn’t ready, queue outgoing audio chunks in memory (small buffer, only until ready).
- **Timeout (5s):** if realtime isn’t ready after 5 seconds, mark realtime unavailable, close the socket, clear buffer, and continue recording locally.
- **On release:**
  - If realtime ready and healthy, commit audio and await completion (existing behavior + release tail).
  - If realtime unavailable or failed, send WAV to REST (existing auto-retry + manual retry).

## Data Flow
1) PTT pressed → `AudioCapture.start` immediately → WAV writer begins.
2) While connecting:
   - Each audio chunk appended to WAV.
   - Each audio chunk appended to `preconnectBuffer` (in memory).
3) Realtime ready:
   - Flip `isRealtimeReady = true`.
   - Flush `preconnectBuffer` to realtime in order.
   - Stream subsequent chunks directly.
4) Timeout at 5s before ready:
   - `isRealtimeTimedOut = true`.
   - Close realtime, clear buffer.
   - Continue WAV capture only.
5) Release:
   - If realtime failed/timed out → REST from WAV.
   - Else commit+await completion.

## State/Flags
- `isRealtimeReady: Bool`
- `isRealtimeTimedOut: Bool`
- `preconnectBuffer: [Data]`
- `connectTimeoutTask: Task<Void, Never>?`
- `connectTimeoutNanos: UInt64` (injectable for tests)

## Error Handling
- Realtime error before ready → treat as timeout; REST on release.
- Realtime error after ready → set `realtimeFailedWhileRecording = true`; REST on release.
- Release before ready → REST on release.

## Memory/Performance
- Preconnect buffer only holds audio until realtime is ready or timeout; worst case (5s at 24kHz mono PCM16) ~240KB.
- Long sessions remain on disk via WAV; no RAM growth.

## UI/UX
- Notch shows “recording” immediately on key-down (no visible “connecting” delay).
- No extra UI needed; existing retry toast covers REST fallback failures.

## Testing
- **Preconnect buffer flush:** audio queued before ready is sent in order once ready.
- **Timeout fallback:** when connect times out, realtime closes, buffer clears, REST used on release.
- **Error before/after ready:** confirm REST fallback on release.
- **Quick tap:** release before ready uses REST.

## Open Questions
None (timeout confirmed at 5s).
