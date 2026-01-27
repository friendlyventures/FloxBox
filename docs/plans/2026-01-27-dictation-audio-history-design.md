# Dictation Wire-Audio History Design

**Date:** 2026-01-27  
**Owner:** FloxBox  
**Goal:** Persist the last five dictation sessions with the actual audio bytes sent over the wire, segmented by server VAD commits, and present them in the Debug panel with per-chunk playback and transcripts.

## Summary

We need consistent, debuggable evidence of what audio was sent to the realtime transcription server. We will record only audio chunks that are successfully sent via the realtime client, group them into server VAD commits using `input_audio_buffer.committed` events, and persist the last five dictation sessions to disk. The Debug panel will show a new “Dictation Audio History” section below the Transcription Prompt, with per-session Play All and per-chunk playback, plus a read-only transcript view for each chunk. The currently playing chunk is highlighted so it is clear which audio segment maps to which transcript.

## Goals

- Persist the last **five dictation sessions** to disk (each session can contain multiple chunks).
- Each chunk must be the **exact PCM data that was sent successfully** to the server.
- Chunk boundaries align to **server VAD commit events** (`input_audio_buffer.committed`).
- Debug panel playback shows which chunk is playing and the associated transcript.

## Non-Goals

- Perfectly reconstruct the server’s internal VAD boundary timestamps (not exposed). We use commit events as boundaries.
- Sharing history outside debug tooling or syncing it.

## Key Decisions

1) **Capture on successful send**
   We only append audio to the history after `client.sendAudio(data)` succeeds. This ensures the WAV files reflect actual bytes sent over the wire, not just captured locally.

2) **Session-first retention**
   We retain the last **five sessions** (Start → Stop), not just five chunks. This keeps complete context for debugging while preserving the commit-level granularity.

3) **Commit events define chunk boundaries**
   When `input_audio_buffer.committed` arrives, we finalize the current chunk WAV and start a new chunk for subsequent sent audio.

## Data Model

```swift
struct DictationSessionRecord: Codable, Identifiable {
    var id: String               // recordingSessionID
    var startedAt: Date
    var endedAt: Date?
    var chunks: [DictationChunkRecord]
}

struct DictationChunkRecord: Codable, Identifiable {
    var id: String               // itemId from input_audio_buffer.committed
    var createdAt: Date
    var wavPath: String
    var byteCount: Int
    var transcript: String
}
```

## Storage Layout

- Base directory: `~/Library/Application Support/FloxBox/Debug/DictationHistory/`
- Index file: `history.json` (array of `DictationSessionRecord`)
- Session directory: `<sessionId>/`
- Chunk WAVs: `chunk-001.wav`, `chunk-002.wav`, …

Retention: keep the five most recent sessions by `startedAt`. When trimming, delete the session directory and remove the entry from `history.json`.

## Capture Flow

- **On start**: create a new `DictationSessionRecord` for `recordingSessionID`, write to in-memory history and persist index.
- **On send success** (`scheduleAudioSend`): append PCM bytes to the active chunk WAV writer via a `WireAudioHistoryRecorder` actor.
- **On commit event** (`input_audio_buffer.committed`): finalize the current chunk WAV, create a `DictationChunkRecord` with the event’s `itemId`, and start a new chunk.
- **On transcription completed** (`input_audio_transcription.completed`): update the matching chunk’s transcript in the index.
- **On stop**: mark `endedAt` for the session; leave last chunk open until next commit or session ends. If the session ends without a final commit, finalize the last chunk with a synthetic `itemId` (e.g., `uncommitted-<timestamp>`), so the audio still appears.

### Boundary Accuracy Note

Commit boundaries are based on **server commit events**. Because commit events arrive asynchronously, there can be slight boundary drift relative to the precise VAD timestamp. We still preserve the full stream of successfully sent audio and keep chunking aligned to server signals as the best available proxy.

## Debug Panel UI

Location: below the “Transcription Prompt” in `DebugPanelView`.

Structure:
- **Dictation Audio History** (GroupBox)
  - For each session (most recent first):
    - Header: timestamp + session id, “Play All” button (primary)
    - Chunk list:
      - Chunk header: chunk index + Play button + duration/bytes
      - Read-only transcript text view
      - Active chunk gets highlighted when playing

Playback:
- A lightweight `WireAudioPlaybackController` handles per-session Play All and per-chunk playback, updates the active chunk id, and advances automatically.

## Error Handling / Edge Cases

- If WAV write fails, log a debug message and continue without history for that chunk.
- If `history.json` is corrupt, fall back to an empty history and recreate.
- If a chunk WAV file is missing on load, drop the chunk from the session.

## Testing Plan

Unit tests:
- Appends audio only after successful send (mock client that fails and verify no bytes).
- Commit event finalizes chunk and creates record.
- Transcription completed updates the chunk transcript.
- Retention trimming keeps only five sessions and deletes old directories.
- Debug panel builds with history section (smoke test).

## Open Questions

- Whether to show partial transcripts (delta) or only completed transcripts (current plan: completed only).
