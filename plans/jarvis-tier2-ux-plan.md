# Tier 2/3 UX Implementation Plan

## Overview

All 11 bugs and Tier 1 UX are complete. This plan covers the remaining 14 Tier 2 and 7 Tier 3 UX improvements across the same 5 files.

---

## Tier 2: Chat Screen (6 items in home_screen.dart)

### UX-1: Message Timestamps
**Current:** `ChatMessage.timestamp` exists but never rendered.
**Plan:** Add a small `Text` widget below each `_ChatBubble` showing time (e.g., "10:30 AM") using `intl.DateFormat`. Only show for user messages (reduce clutter). Format: `jm()` from `package:intl`.
**Complexity:** Low — add 3 lines to `_ChatBubble.build()`, import `intl`.

### UX-2: Copy-to-Clipboard
**Current:** No interaction on bubbles.
**Plan:** Wrap `_ChatBubble` with `GestureDetector` → `onLongPress` → `showMenu` with "Copy" → `Clipboard.setData(ClipboardData(text: text))`. Only for non-system messages.
**Complexity:** Low — wrap existing widget, add `Clipboard` + `showMenu`.

### UX-5: Haptic Feedback (mic + send)
**Current:** `HapticFeedback.lightImpact()` was added on send in the bug fixes. Mic tap has no haptic.
**Plan:** Add `HapticFeedback.mediumImpact()` inside `_MicButton.onTap` before calling `onTap` callback. The `vibration` package is already in pubspec.yaml.
**Complexity:** Trivial — 1 line addition.

### UX-6: Listening Animation
**Current:** Static red circle with `AnimatedContainer` color change.
**Plan:** Convert `_MicButton` to `StatefulWidget` with `AnimationController`. During `listening` state, apply a `Transform.scale` with `sin`-based pulsing (1.0 ↔ 1.15 scale). Keep red color. On stop, animate back to normal.
**Complexity:** Medium — needs `AnimationController`, `SingleTickerProviderStateMixin`, cleanup in `dispose`.

### UX-7: Typing Indicator
**Current:** Streaming bubble with `CircularProgressIndicator` only appears when `currentResponse` is non-empty.
**Plan:** When `sessionState == thinking` and `currentResponse.isEmpty`, show a dedicated "J.A.R.V.I.S. is typing..." bubble with animated dots (three `Container` dots with staggered opacity animation). Use a `_TypingIndicator` widget inserted into the ListView when applicable.
**Complexity:** Medium — needs `AnimationController` for staggered dot animation, conditional insertion in ListView items.

### UX-8: Date Separators
**Current:** No date grouping between messages.
**Plan:** Pre-process the message list to insert date-separator items. Compare consecutive `ChatMessage.timestamp` dates. Show "Today", "Yesterday", or formatted date as centered system-style text between groups. Use `intl` for formatting.
**Complexity:** Medium — requires list pre-processing via a helper function that returns a list of `(isSeparator, dateLabel, message?)` tuples. Modify `_ChatMessages` item builder.

---

## Tier 2: Settings Screen (3 items in settings_screen.dart)

### UX-11: LLM Config Read-Only Indicator
**Current:** LLM config values shown as plain `ListTile` subtitles with no indication they're read-only.
**Plan:** Add a small lock icon (`Icons.lock_outline`, 14px) or change subtitle to "model-id · configured in .env". Simple text change.
**Complexity:** Trivial — modify subtitle strings.

### UX-13: App Version
**Current:** Static "J.A.R.V.I.S. Phase 1" / "Prototype — Pixel 7 / Android 16+" text.
**Plan:** Show version from `pubspec.yaml` (1.0.0+1). Cannot read pubspec.yaml at runtime without `package_info_plus`. Two options:
- **Option A:** Add `package_info_plus` dependency (adds ~200KB). Read `version` + `buildNumber`.
- **Option B:** Hardcode as `const String appVersion = '1.0.0 (build 1)'` in a config file. Simpler, no new dependency.
  **Recommendation:** Option B for now. Create `lib/config/app_config.dart` with version constant.
**Complexity:** Low (Option B) or Medium (Option A — new dependency).

### UX-14: Biometric Toggle Loading
**Current:** `SwitchListTile.onChanged` calls `authNotifier.setBiometricEnabled(value)` synchronously in the UI — no loading state.
**Plan:** Add a `_biometricToggling` boolean state. Set to `true` before async call, `false` after. While `true`, show `CircularProgressIndicator` (16px) instead of the switch.
**Complexity:** Low — add state variable, conditional widget in SwitchListTile.

---

## Tier 2: Memory Screen (2 items in memory_screen.dart)

### UX-17: Memory Timestamps
**Current:** `UserMemory` has `createdAt` field but it's not displayed.
**Plan:** Add a subtitle line to each memory `ListTile` showing "Created: {formatted date}" using `intl.DateFormat`. Show below the value text.
**Complexity:** Low — add `intl` import, format `m.createdAt`.

### UX-20: Pull-to-Refresh
**Current:** No way to refresh memory list without navigating away and back.
**Plan:** Wrap the `FutureBuilder` content with `RefreshIndicator`. Extract the future to a `_loadMemories()` method stored in state. On refresh, call `setState` to re-trigger the FutureBuilder.
**Complexity:** Low-Medium — needs refactoring of how the FutureBuilder future is managed (similar to BUG-4 fix pattern).

---

## Tier 2: Auth Screen (3 items in auth_screen.dart)

### UX-21: Biometric Auto-Prompt
**Current:** User must tap biometric button manually.
**Plan:** In `initState`, after `_checkBiometricAvailability()` completes, if `_isBiometricAvailable && _isBiometricEnabled`, call `_attemptBiometric()` automatically. Use a short delay (300ms) to let the UI render first. Guard against double-trigger with `_autoPrompted` flag.
**Complexity:** Low — add delayed auto-call in `_checkBiometricAvailability`.

### UX-22: PIN Dot Shake Animation
**Current:** On incorrect PIN, dots clear but no animation.
**Plan:** Add `AnimationController` for horizontal shake. On `PinFailure`, trigger `_shakeAnimationController.forward().then((_) => _shakeAnimationController.reset())`. Wrap the PIN dots `Row` with `AnimatedBuilder` → `Transform.translate(offset: Offset(sin(...) * 8, 0))`.
**Complexity:** Medium — needs `AnimationController`, `SingleTickerProviderStateMixin`, integration with existing PIN verification flow.

### UX-24: PIN Haptic Feedback
**Current:** No haptic on PIN digit entry.
**Plan:** In `_onPinChanged`, when a new digit is added (length increased), call `HapticFeedback.selectionClick()`. The `vibration` package is already a dependency; Flutter's `HapticFeedback` is from `flutter/services.dart` (already imported).
**Complexity:** Trivial — 1 line in `_onPinChanged`.

---

## Tier 3: Settings (1 item)

### UX-12: Lock App Now Button
**Current:** No way to manually lock the app.
**Plan:** Add a "Lock App Now" `ListTile` in the SECURITY section. On tap, call `authNotifier.lock()` to transition to `AuthState.locked`, which triggers `AuthGate` to show the lock screen.
**Complexity:** Low — check if `authNotifier` has a `lock()` method; if not, add one.

---

## Tier 3: Memory Screen (4 items in memory_screen.dart)

### UX-15: Search/Filter Bar
**Current:** No search. Database has `queryMemories(category?, keyword?)` ready.
**Plan:** Add a `TextField` search bar in the AppBar or below it. On text change, call `db.queryMemories(keyword: query)` instead of `db.getAllMemories()`. Debounce 300ms.
**Complexity:** Medium — needs search state management, debounce timer, query rewrite.

### UX-16: Swipe-to-Delete
**Current:** Trash icon + confirmation dialog.
**Plan:** Wrap each memory `Card` with `Dismissible` widget. `confirmDismiss` shows the existing confirmation dialog. `onDismissed` calls `db.deleteMemory()`. Add red background with delete icon on swipe.
**Complexity:** Low-Medium — wrap existing Card widget.

### UX-18: Bulk Delete ("Clear All Memories")
**Current:** One-by-one deletion only.
**Plan:** Add "Clear All Memories" in AppBar overflow menu (`PopupMenuButton` with one item). Show confirmation dialog. On confirm, iterate and delete all memories, then refresh.
**Complexity:** Low — AppBar action + confirmation + loop delete.

### UX-19: Edit Memory Inline
**Current:** Delete + re-add via conversation only.
**Plan:** Add an edit icon button next to the delete button on each card. On tap, show a dialog with a `TextFormField` pre-filled with current value. On save, call `db.upsertMemory()` with new value.
**Complexity:** Medium — new dialog, upsert call.

---

## Tier 3: Auth Screen (2 items)

### UX-23: Forgot PIN Recovery
**Current:** Permanent lockout after too many attempts (no recovery).
**Plan:** Needs design discussion. Options: (a) security question set during first PIN setup, (b) reset via biometric re-auth, (c) backup code. Added as a "Reset PIN" button on lock screen that triggers biometric verification before allowing reset.
**Complexity:** High — needs architectural design + new auth flow.

### UX-25: Move Change PIN to Post-Auth
**Current:** "Change PIN" button visible on lock screen (pre-auth).
**Plan:** Remove the `TextButton.icon` from the lock screen `Column`. The button already exists in `settings_screen.dart`. This is a one-line removal.
**Complexity:** Trivial — delete the button from auth_screen.dart.

---

## Implementation Order

| Batch | Items | File(s) | Complexity |
|-------|-------|---------|------------|
| **A** | UX-5 (haptic mic), UX-24 (haptic PIN), UX-11 (read-only label), UX-13 (version), UX-25 (remove Change PIN from lock) | 3 files | Trivial |
| **B** | UX-1 (timestamps), UX-2 (copy-to-clipboard), UX-14 (biometric loading), UX-17 (memory timestamps), UX-20 (pull-to-refresh), UX-21 (auto-prompt biometric) | 3 files | Low |
| **C** | UX-6 (listening animation), UX-7 (typing indicator), UX-8 (date separators), UX-22 (PIN shake) | 2 files | Medium |
| **D** | UX-12 (lock button), UX-16 (swipe-to-delete), UX-18 (bulk delete), UX-19 (edit memory), UX-15 (search/filter) | 2 files | Medium |
| **E** | UX-23 (forgot PIN recovery) | 1 file | High — design first |

---

## Dependencies Available

| Asset | Status |
|-------|--------|
| `intl: ^0.19.0` | Already in pubspec.yaml (UX-1, UX-8, UX-17) |
| `vibration: ^2.0.0` | Already in pubspec.yaml (UX-5, UX-24) |
| `flutter/services.dart` | Already imported in most files (HapticFeedback, Clipboard) |
| `UserMemory.createdAt` | Database column exists (UX-17) |
| `db.queryMemories(keyword:)` | Database method exists (UX-15) |
| `db.upsertMemory()` | Database method exists (UX-19) |
