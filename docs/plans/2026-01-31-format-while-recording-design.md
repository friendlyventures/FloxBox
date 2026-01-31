# Format-While-Recording Design

## Why
We want formatted, sendable text without post-stop latency. Today we format only after the final transcript, which makes `stop → paste` too slow for the 200+ wpm goal. We will keep formatting **always-on**, but shift it **into the recording window** by formatting incremental chunks.

## Goals
- Always format output (remove disfluencies, fix punctuation/paragraphs, apply glossary).
- Achieve ≥200 wpm effective speed (from start of recording to text paste).
- Preserve paragraph structure with **blank-line separation**.
- Keep reliability: failures should degrade gracefully without blocking insertion.

## Non-Goals
- Replace the ASR model or remove formatting.
- Change insertion mechanics (clipboard/AX/CG) beyond required for this pipeline.
- Major UI changes beyond existing notch states.

## Approach Overview
### Key change
Disable VAD turn detection for the session and **manually commit audio on a fixed cadence** (default 1000 ms). Each commit yields a completed transcription segment. We **buffer segments** into small logical groups and format them **during recording**, so the final paste is waiting only on the tail.

### Flow
1. Start recording → set `vadMode = .off` for the session update.
2. Start a **manual commit ticker** (every 1000 ms).
3. For each `transcription_completed` event:
   - Append raw text to `TranscriptStore` (existing behavior).
   - Enqueue the segment into a **FormattingBuffer**.
4. When the buffer is ready (word threshold or topic shift cue):
   - Format the buffered text with a **context stub** (last 1–2 formatted sentences).
   - Append output to `FormattedTranscriptStore`.
5. On stop:
   - Force one final commit.
   - Flush remaining buffer and await its formatting.
   - Insert `FormattedTranscriptStore.displayText`.

## New Components
### ManualCommitController
- Starts after the realtime session update succeeds.
- Calls `client.commitAudio()` every 1000 ms while recording.
- Stops on PTT release.

### FormattingBuffer
- Accumulates completed segments until:
  - >= 12–20 words, OR
  - topic shift cue (e.g., "next," "also," "new paragraph,").
- Emits a buffer payload for formatting.
- Maintains a short **context stub** to preserve sentence flow.

### FormattedTranscriptStore
- Ordered store of formatted chunks.
- Produces `displayText` for insertion.
- Maintains paragraph spacing with blank lines.

## Formatting Behavior
- Always use the existing `FormattingPipeline`.
- Prompt already requires **blank-line paragraph separation**.
- Use `FormatValidator` to prevent drift.
- If formatting fails for a chunk, retry once; then fall back to raw chunk text **only for that chunk**.

## Error Handling
- If realtime fails entirely → use existing REST fallback and format the full transcript after REST completion (current behavior).
- If formatting fails for a chunk → use raw chunk text for that chunk, continue with rest of pipeline.
- If final chunk formatting is slow → wait briefly; avoid inserting unformatted text unless explicitly allowed (future option).

## Telemetry / Metrics
Log per session:
- `t_start`, `t_first_text`, `t_stop`, `t_last_commit`, `t_insert`
- `word_count`
- computed `wpm = word_count / (t_insert - t_start) * 60`

## Tests
- Unit tests for `FormattingBuffer` (thresholds, cue triggers, flush behavior).
- Unit tests for `FormattedTranscriptStore` ordering + blank-line joins.
- Integration test simulating sequential `transcription_completed` events and ensuring final insertion uses formatted output.

## Rollout Plan
- Phase 1: add instrumentation and buffer/formatter queue with VAD still on (to validate behavior).
- Phase 2: switch to manual commit mode (vad off) with 1000 ms ticker.
- Phase 3: tune buffer size and cue list based on real sessions.

