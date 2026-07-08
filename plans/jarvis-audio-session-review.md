# JARVIS — Audio Session Bug Review & Validation

> **Date:** 2026-07-08
> **Source:** ADB logcat from Pixel 7 / Android 16+ debug build
> **Review Goal:** Validate every proposed fix against the actual log evidence and refine the implementation plan.

---

## Log Evidence Re-examined

```
SESSION 1
══════════
13:00:50  connect()
13:00:51  Connected; mic started; session started
13:00:59  Tool call: tavily_search
13:01:18  Barge-in (user interrupted while tool was running)
13:01:18  Turn complete → no audio (buffer cleared by barge-in) ✓
13:01:24  Turn complete → TTS 172,800 bytes → plays fine
13:01:29  Mic restarted
13:01:50  Barge-in
13:01:50  Turn complete → no audio (buffer cleared)
13:02:07  Turn complete → TTS 840,960 bytes → plays fine
13:02:09  NEW connect() (session recreated — likely user tapped mic)

SESSION 2 (problematic)
═══════════════════════
13:02:09  Connected; loaded 2 history msgs; mic started; session started
13:02:09  → User speaks; NO response logged for ~7 seconds
13:02:16  TTS 288,000 bytes → audible response
13:02:19  TTS playback completed; mic restarted
13:02:30  Turn complete ×2 (2 ms apart) → TTS 1,056,000 ×2 → STUTTER
13:02:36  LiveSessionClosedException code 1002
13:02:36  Reconnect attempt
13:02:37  DNS failure: generativelanguage.googleapis.com
```

---

## Fix-by-Fix Validation

### FIX-1: Double turn-complete race — ✅ CONFIRMED

**Log proof:**

```
13:02:30.948  Model turn complete — signalling commit
13:02:30.948  Turn complete — committing response
13:02:30.949  Playing TTS audio: 1056000 raw PCM bytes
13:02:30.950  Model turn complete — signalling commit
13:02:30.950  Turn complete — committing response
13:02:30.950  Playing TTS audio: 1056000 raw PCM bytes
```

Both events produced a `Playing TTS audio` log. The `_isPlayingAudio` guard in `_playBufferedAudio()` did **not** skip the second call, which means the guard either:
- Was reset in the first call's `finally` block before the second call checked it, or
- The first call's `await _audioPipeline?.stopListening()` yielded and the second call raced through before `_isPlayingAudio` was set.

The primary failure, however, is the `_isCommitting` guard in `_commitResponse()`: it resets at line 555 immediately because `_playBufferedAudio()` is **not awaited**. With two events 2 ms apart, the second `_commitResponse()` passes the guard and triggers a second playback attempt.

**Verdict:** The proposed fix — make `_commitResponse()` `async` and `await _playBufferedAudio()` — is correct and sufficient. It serializes the two callbacks because the `turnComplete` stream listener is `async` and won't deliver the next event until its Future completes.

---

### FIX-2: VAD warm-up delay — ⚠️ PARTIALLY CONFIRMED, NEEDS REFINEMENT

**Log evidence:**
- New session starts at 13:02:09
- User speaks immediately after 13:02:09
- No response is logged until 13:02:16 (7-second gap)

The 7-second gap is too long to be only VAD calibration. It is more likely:
1. The first utterance was **not detected** by the server-side VAD (which is still calibrating), and
2. The audible response at 13:02:16 was actually for a **second/later** utterance the user spoke during that window.

A 500 ms warm-up delay alone is therefore insufficient to explain and fix the problem. The delay helps the VAD, but we also need to either:
- Buffer the first ~500 ms of audio and send it after warm-up, or
- Start the mic before the session is ready and hold frames locally, or
- At minimum add detailed logging to confirm whether frames are being sent and whether `ServerContent` events arrive.

**Verdict:** Keep the 500 ms warm-up, but add:
- A `connecting` state during warm-up so the user knows not to speak yet
- Mic-frame counters and a log when the first `ServerContent` arrives
- Consider a small audio buffer in `AudioPipeline` that flushes after warm-up (optional, more complex)

---

### FIX-3: State-specific hint text — ✅ CONFIRMED

**Log / UX evidence:**
- The `_InputBar` currently shows `'J.A.R.V.I.S. is responding...'` for **all** active states (listening, thinking, speaking).
- When the user is actually speaking during `listening`, the hint is misleading.

**Verdict:** Replace with `switch` based on `ChatSessionState`. This is a safe, high-impact UI fix.

---

### FIX-4: Deduplicate "Listening" status — ✅ CONFIRMED

**Log / UX evidence:**
- `startSession()` adds a system chat message `'Listening...'` (line 268).
- The app bar `_ConnectionIndicator` already shows a green dot + "Listening" label.
- The user sees the same status in two places.

**Verdict:** Remove the system message and its cleanup filters in `stopListening()` / `endSession()`. Keep the app bar indicator as the single source of truth.

---

### FIX-5: Mic auto-restart confusion — 🔄 REVISED

**Original plan:** Offer two options, recommend continuous conversation with better visual feedback.

**User complaint:** *"the microphone stays on which is misleading"*

The user is explicitly saying the mic should not remain active after JARVIS responds. The current continuous-conversation model keeps the mic on indefinitely until the user taps to stop. This is the source of the confusion.

**Revised recommendation:** Change to a **turn-based default** after each response:
- After TTS playback completes, set `sessionState` to `idle` and stop the mic.
- The user must tap the mic button again to start the next exchange.
- This matches the mental model of Siri/Alexa-style voice assistants: tap-to-talk → response → idle.

**Trade-off:** We lose the ability to barge in during JARVIS's speech (because the mic is off during playback anyway). If barge-in is a desired feature, it can be added later as an explicit "always listening" mode in Settings.

**Verdict:** Implement turn-based idle-after-response. Update the mic button to show a clear "tap to talk" state when idle. This directly addresses the user's complaint.

---

### FIX-6: Stream error handling — 🔄 REVISED

**Original plan:** Focus on stopping "reconnect spam".

**Log evidence:** The log shows **only one** reconnection attempt (13:02:36 → 13:02:37), then it stops. So "reconnect spam" is not the issue in this trace.

The real issues are:
1. The generic error message: *"Connection lost. Tap mic to retry."* — does not distinguish a network failure from an API/auth failure.
2. When the reconnect immediately hits a DNS failure (`SocketException: No address associated with hostname`), the retry loop is wasted.
3. The error is not surfaced in the chat UI until the connection-state listener fires, which may lag.

**Revised recommendation:**
- Detect DNS/network failures in `_handleStreamError` and set `_retryCount = _maxRetries` to prevent further retries.
- Categorize errors: `network`, `auth`, `server`, `unknown`.
- Provide specific UI messages:
  - Network: *"Network unavailable. Check your connection and tap mic to retry."*
  - Auth: *"API key invalid. Check Settings."*
  - Server: *"JARVIS service unavailable. Tap mic to retry."*

**Verdict:** Keep the fix but reframe it around error categorization and actionable messaging, not spam prevention.

---

### FIX-7: Transcriptions — ✅ CONFIRMED, DEFER

**Log evidence:** Audio is sent directly via `sendAudio()`. No text representation of the user's speech is ever produced or logged.

**Verdict:** Correctly deferred. This requires client-side STT or a transcription API and should be its own feature plan.

---

## Additional Observations

1. **Session recreation at 13:02:09:** The previous session finished cleanly at 13:02:07, but a new `connect()` was called at 13:02:09 with no preceding error. This suggests the user tapped the mic to stop and immediately restart, or the UI triggered a new session. This does not require a code fix, but it reinforces that the UX should make session lifecycle clearer.

2. **Barge-in works correctly:** In Session 1, barge-in cleared the audio buffer and the subsequent turn-complete correctly committed no audio. This is a healthy signal that the barge-in pipeline is functioning.

3. **Tool call in Session 1:** The `tavily_search` tool call took ~18 seconds before the user barged in. Tool latency may have contributed to the user interrupting. This is not a bug, but a performance/UX consideration.

4. **Audio resampling is correct:** The 24 kHz → 48 kHz upsample is still needed; no changes required there.

---

## Updated Implementation Order

```
FIX-1 → FIX-2 (with logging) → FIX-6 → FIX-3 → FIX-4 → FIX-5 → FIX-8 → FIX-7
```

| Order | Fix | Status | Notes |
|-------|-----|--------|-------|
| 1 | FIX-1 | ✅ Confirmed | Critical race; await `_playBufferedAudio` |
| 2 | FIX-2 | ⚠️ Refined | Add 500 ms warm-up + connection logging |
| 3 | FIX-6 | 🔄 Refined | Error categorization + network retry stop |
| 4 | FIX-3 | ✅ Confirmed | State-specific hints |
| 5 | FIX-4 | ✅ Confirmed | Remove duplicate system message |
| 6 | FIX-5 | 🔄 Refined | Turn-based idle after response |
| 7 | FIX-8 | ➕ Added | Stop button to interrupt LLM and accept fresh input |
| 8 | FIX-7 | ✅ Confirmed | Defer to transcription plan |

---

## Additional User-Requested Change (FIX-8)

A **Stop** button to interrupt JARVIS mid-response was added after the log review. This is not visible in the logs but is a direct UX requirement:
- Show a red stop button when state is `thinking` or `speaking`.
- Tapping it stops playback, clears the audio buffer, discards the partial response, and transitions to `listening` (or `idle` if turn-based mode is chosen).
- This depends on FIX-1 (stable commit/playback) and FIX-5 (mic state model).

---

## Files to Modify

| File | Fixes |
|------|-------|
| `lib/providers/chat_provider.dart` | FIX-1, FIX-2, FIX-5, FIX-8 |
| `lib/services/gemini_live_provider.dart` | FIX-6 |
| `lib/ui/screens/home_screen.dart` | FIX-3, FIX-4, FIX-8 |
