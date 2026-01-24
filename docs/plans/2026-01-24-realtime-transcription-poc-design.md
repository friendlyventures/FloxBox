# Realtime Transcription PoC Design

## Summary
Build a macOS 14.6 SwiftUI app (Swift 6.2+) that records microphone audio and streams it to OpenAI Realtime transcription. The UI is a single window with a model picker, VAD controls (including tuning), Start/Stop, Clear, and a live transcript view. The app supports live incremental transcription while recording and provides a fast way to compare models and VAD settings.

## Goals
- Prove live, realtime transcription on macOS.
- Allow precise model selection (all supported realtime transcription identifiers except diarization).
- Allow experimentation with VAD modes and tuning.
- Keep UI minimal and settings visible for quick iteration.

## Non-goals
- Conversation or assistant responses.
- Multi-user or diarization use cases.
- Polish, onboarding, or advanced settings persistence.

## Supported Models (Dropdown)
- gpt-4o-transcribe (default)
- gpt-4o-transcribe-latest
- gpt-4o-mini-transcribe
- gpt-4o-mini-transcribe-2025-12-15
- whisper-1

## UI Layout (Single Window)
- Top row: Model picker, VAD Mode selector.
- VAD Mode:
  - Off
  - Server VAD
  - Semantic VAD
- If VAD Mode = Off: Commit Interval selector (Off, 1s, 2s, 3s, 4s, 5s). Default 2s.
- If VAD Mode = Server VAD: show tuning fields
  - threshold (0.0 to 1.0, optional)
  - prefix_padding_ms (optional)
  - silence_duration_ms (optional)
  - idle_timeout_ms (optional)
- Controls: Start/Stop (primary), Clear (secondary).
- Transcript area: large, scrollable text view with live deltas and finalized segments.
- Status line: Idle / Connecting / Recording / Error with short message.

## Architecture
- AudioCapture
  - AVAudioEngine input tap.
  - Convert to 24 kHz mono PCM16 (little-endian).
  - Emit fixed-size frames (e.g., 20-40 ms) into a ring buffer.
- RealtimeClient
  - URLSessionWebSocketTask to OpenAI Realtime.
  - On connect, send session config for transcription (model, input format, VAD mode).
  - Send input_audio_buffer.append with base64 PCM chunks.
  - If VAD Mode = Off and Commit Interval > 0, send input_audio_buffer.commit on timer.
  - On Stop, send final commit (if VAD Off) then close after completions.
- TranscriptStore
  - Track segments by item_id.
  - Apply delta events to current segment text.
  - Apply completed events to finalize and order segments (handle out-of-order arrivals).
  - Provide combined display text (finalized + live current segment).

## Data Flow
1. Start pressed.
2. Request microphone permission if needed.
3. Open WebSocket and send session config.
4. Start audio engine and stream audio chunks via append events.
5. Receive delta/completed events; update TranscriptStore; UI updates live.
6. Stop pressed.
7. Stop audio engine; commit if needed; wait for completions; close socket.

## VAD Behavior
- VAD Mode only affects when the server commits audio to a segment; it does not stop recording.
- Server VAD uses defaults unless the user sets tuning fields (only include overridden fields in config).
- Semantic VAD uses default eagerness (auto) for the PoC.
- VAD Off uses manual commits; Commit Interval controls live updates. Off means only on Stop.

## Error Handling
- Missing mic permission: show error; do not start recording.
- WebSocket failure: stop recording, surface error, keep transcript.
- Malformed events: ignore safely, log in DEBUG only.
- Audio engine failure: stop and show error.

## Debug Logging
- Use #if DEBUG guards.
- Log outbound session config, append/commit counts, and inbound event summaries.

## Testing
- Unit tests for TranscriptStore ordering and delta/completion merging.
- Unit tests for VAD config serialization (defaults omitted vs overrides included).
- Integration smoke test using a short audio file through the pipeline with a mocked WebSocket layer.

## Assumptions
- OpenAI API key provided via local developer configuration (not committed).
- No persistence for VAD settings in the PoC (in-memory only).
