# Push-To-Talk Realtime + REST Retry Design

**Date:** 2026-01-26  
**Owner:** FloxBox  
**Goal:** Push-to-talk always yields a complete transcription after release. If realtime fails, we retry once via REST with a saved WAV, then allow manual retry.

## Summary

Push-to-talk should define a hard end-of-utterance boundary on release. To guarantee we still receive the final transcription, we must keep the realtime session open until `input_audio_transcription.completed` arrives. If the realtime socket dies, we continue recording locally and send the saved WAV to REST on release. We retry once automatically after a short delay, then surface a manual retry action in the notch.

## Root Cause (Current Failure)

`TranscriptionViewModel.stopInternal()` closes the realtime WebSocket immediately after stopping audio. Transcription completes asynchronously after commit, so the completed event arrives after release and is missed. Result: “Test one two three” produces nothing.

## Key Decisions

1) **Push-to-talk uses VAD off**  
   Set `turn_detection` to `null` for PTT so the client commits explicitly on release. This gives deterministic boundaries and avoids VAD latency.

2) **Explicit commit on release (only if buffered audio)**  
   `input_audio_buffer.commit` errors if the buffer is empty. Track `hasBufferedAudio` and only commit when true.

3) **Keep realtime session alive until completion**  
   After commit, wait for `conversation.item.input_audio_transcription.completed` before closing the socket.

4) **Always capture a local WAV (latest-only)**  
   Write PCM16 24kHz mono to a WAV file while recording. Keep only the latest file. On success, delete any older file and keep the most recent for safety.

5) **Automatic REST retry once**  
   If realtime fails or times out, send WAV to REST `/v1/audio/transcriptions`. If it fails once, wait 2s and retry once. Then surface manual retry.

## Realtime Flow (PTT)

Press:
- `input_audio_buffer.clear`
- start mic capture
- stream PCM16 chunks via `input_audio_buffer.append`
- write identical PCM to WAV file

Release:
- stop mic and flush final chunk
- if `hasBufferedAudio`:
  - send `input_audio_buffer.commit`
  - wait for `input_audio_transcription.completed` for the committed item
- only then close realtime socket

If realtime disconnects mid-utterance:
- keep recording locally
- on release, skip realtime and go to REST transcription

## REST Retry Flow

Primary fallback:
- POST `/v1/audio/transcriptions` with WAV + model
- on success: update transcript, clear retry state

Auto-retry:
- wait 2 seconds, retry once
- show toast “Retrying…”

Manual retry:
- if second failure, show notch action “Retry”
- uses the same saved WAV

## State Machine (High-Level)

States:
- Idle
- Recording (realtime connected)
- Recording (realtime failed)
- AwaitingCompletion (after commit)
- RestRetrying
- ManualRetryReady

Transitions:
- Recording → AwaitingCompletion on release + commit
- AwaitingCompletion → Idle on completed
- Any → RestRetrying on realtime error/timeout
- RestRetrying → ManualRetryReady after second REST failure

## WAV Retention

- Always keep the **latest** WAV file
- Overwrite on each new utterance
- Delete any older files on success
- Keep the latest file even after success (safety requirement)

## UI / Notch

- While recording: show normal recording UI
- On auto-retry: toast “Retrying…”
- On manual retry available: notch action “Retry”

## Observability

Log:
- realtime commit sent (with item id when committed event arrives)
- realtime completed received
- realtime error / disconnect
- REST attempt #1 / #2 results
- WAV path for latest recording

## Testing Plan

Unit tests (mock realtime + REST):
- Release after PTT still yields completed transcript (socket stays open)
- Realtime failure mid-utterance triggers REST on release
- REST auto-retry occurs once with 2s delay
- Manual retry surfaces after second REST failure
- WAV retention: only latest is kept
