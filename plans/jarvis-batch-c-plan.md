# Batch C: Animation Work — Detailed Implementation Plan

## Files: home_screen.dart (3 items) + auth_screen.dart (1 item)

---

## UX-6: Pulsing Mic Animation (home_screen.dart)

**Current state:**
- `_MicButton` is a `StatelessWidget` (line 652)
- Uses `AnimatedContainer` for color/size transitions (300ms)
- Shows red circle during active states, primary color otherwise

**Implementation:**
Convert `_MicButton` to `StatefulWidget` with `SingleTickerProviderStateMixin`.

```
_MicButton (StatefulWidget)
  ├── AnimationController _pulseController
  ├── initState: init controller, listen to state changes via didUpdateWidget
  ├── didUpdateWidget: if state changed to listening → forward(); else → reverse()
  └── build: wrap AnimatedContainer in AnimatedBuilder → Transform.scale
```

**Pulse animation details:**
- Duration: 800ms, repeating
- Curve: `Curves.easeInOut`
- Scale range: 1.0 → 1.12 → 1.0 (subtle)
- Only active during `ChatSessionState.listening`
- On state transition away from listening → `_pulseController.reverse()` (returns to scale 1.0)

**Code structure:**
```dart
class _MicButton extends StatefulWidget { ... }

class _MicButtonState extends State<_MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
    // Start paused — only run when listening
    _pulseController.stop();
    _syncPulse(widget.state);
  }

  void _syncPulse(ChatSessionState state) {
    if (state == ChatSessionState.listening) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant _MicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _syncPulse(widget.state);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Wrap existing AnimatedContainer in AnimatedBuilder
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) => Transform.scale(
        scale: _pulseAnim.value,
        child: child,
      ),
      child: GestureDetector(
        // ... existing mic button code unchanged ...
      ),
    );
  }
}
```

**Edge cases:**
- `connecting` state: shows spinner, no pulse
- `thinking`/`speaking`: stop icon, no pulse
- Widget rebuild from parent: `didUpdateWidget` handles state sync

---

## UX-7: Typing Indicator (home_screen.dart)

**Current state:**
- Streaming bubble shows `CircularProgressIndicator` when `currentResponse.isNotEmpty`
- No visual feedback during the gap between `thinking` state start and first text arrival

**Implementation:**
Add a `_TypingIndicator` widget shown in the ListView when:
- `sessionState == ChatSessionState.thinking`
- `currentResponse.isEmpty`

The typing indicator shows 3 animated dots with staggered opacity.

**Changes needed:**

1. Pass `sessionState` to `_ChatMessages`:
```dart
_ChatMessages(
  messages: chatData.messages,
  currentResponse: chatData.currentResponse,
  scrollController: _scrollController,
  isNearBottom: _isNearBottom,
  sessionState: chatData.sessionState,  // NEW
),
```

2. Add `_TypingIndicator` widget (new stateless widget):
```dart
class _TypingIndicator extends StatefulWidget {
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomLeft: const Radius.circular(4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            return AnimatedBuilder(
              animation: _controller,
              builder: (_, __) {
                final t = (_controller.value - delay).clamp(0.0, 1.0);
                final opacity = (t < 0.5 ? t * 2 : 2 - t * 2).clamp(0.2, 1.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary.withAlpha((opacity * 180).round()),
                    ),
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }
}
```

3. Update `_ChatMessages.itemCount` and `itemBuilder`:
```dart
final showTypingIndicator = sessionState == ChatSessionState.thinking && currentResponse.isEmpty;
final itemCount = messages.length + (currentResponse.isNotEmpty ? 1 : 0) + (showTypingIndicator ? 1 : 0);

itemBuilder: (context, index) {
  // Typing indicator at the end when thinking with no text yet
  if (showTypingIndicator && index == itemCount - 1) {
    return const _TypingIndicator();
  }
  // ...
}
```

**Edge cases:**
- Text arrives during typing indicator → indicator removed, streaming bubble shown
- Session transitions from thinking → speaking → indicator gone
- No typing indicator when messages are empty and session is idle

---

## UX-8: Date Separators (home_screen.dart)

**Current state:**
- Messages listed in chronological order with no date grouping

**Implementation:**
Pre-process messages to insert date separator items. A date separator is a system-style message showing "Today", "Yesterday", or formatted date.

**Helper function:**
```dart
/// Returns a list where messages are interleaved with date separators.
/// Each item is either a ChatMessage or a date label String.
List<Object> _withDateSeparators(List<ChatMessage> messages) {
  if (messages.isEmpty) return [];
  
  final result = <Object>[];
  DateTime? lastDate;
  
  for (final msg in messages) {
    final msgDate = DateUtils.dateOnly(msg.timestamp);
    if (lastDate == null || msgDate != lastDate) {
      result.add(_dateLabel(msgDate));
      lastDate = msgDate;
    }
    result.add(msg);
  }
  return result;
}

String _dateLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateUtils.dateOnly(now);
  final yesterday = today.subtract(const Duration(days: 1));
  
  if (date == today) return 'Today';
  if (date == yesterday) return 'Yesterday';
  return DateFormat('EEEE, MMM d').format(date); // "Monday, Jul 7"
}
```

**Changes in `_ChatMessages`:**
- Call `_withDateSeparators(messages)` to get the interleaved list
- In `itemBuilder`, check if item is a `String` (separator) or `ChatMessage` (bubble)
- Render separators as centered system-style text (same as existing `_ChatBubble(isSystem: true)`)

```dart
final items = _withDateSeparators(messages);
final showTyping = ...;
final itemCount = items.length + (currentResponse.isNotEmpty ? 1 : 0) + (showTyping ? 1 : 0);

itemBuilder: (context, index) {
  if (showTyping && index == itemCount - 1) return const _TypingIndicator();
  if (index == items.length && currentResponse.isNotEmpty)
    return _ChatBubble(text: currentResponse, isUser: false, isStreaming: true);
  
  final item = items[index];
  if (item is String) {
    // Date separator
    return _ChatBubble(text: item, isSystem: true);
  }
  final msg = item as ChatMessage;
  return _ChatBubble(
    text: msg.text,
    isUser: msg.isUser,
    isSystem: msg.isSystem,
    timestamp: msg.timestamp,
  );
}
```

**Edge cases:**
- Empty message list: no separators
- Single-day conversation: one "Today" header
- Multi-day: separators between each day boundary
- Streaming response: never has a date separator (not a persisted message)

---

## UX-22: PIN Dot Shake Animation (auth_screen.dart)

**Current state:**
- On `PinFailure`, dots clear and error message shown
- Line 106 has a comment `// Shake animation trigger` but no actual animation

**Implementation:**
Add `AnimationController` for horizontal shake. Wrap the PIN dots `Row` (line 278) in `AnimatedBuilder` → `Transform.translate`.

**Changes:**
1. Add mixin and controller:
```dart
class _AuthScreenState extends ConsumerState<AuthScreen>
    with SingleTickerProviderStateMixin {
  // ... existing fields ...
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -4, end: 4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 4, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeInOut,
    ));
    // ... rest of initState ...
  }
```

2. Trigger shake on PIN failure:
```dart
case PinFailure(:final remainingAttempts):
  _pinController.clear();
  _previousPinLength = 0;
  setState(() {
    _isAuthenticating = false;
    _errorMessage = 'Incorrect PIN — $remainingAttempts attempts remaining';
  });
  _shakeController.forward(from: 0);  // Trigger shake
  _pinFocusNode.requestFocus();
```

3. Wrap PIN dots in AnimatedBuilder:
```dart
// Visual PIN dots — wrapped with shake animation
AnimatedBuilder(
  animation: _shakeAnim,
  builder: (context, child) => Transform.translate(
    offset: Offset(_shakeAnim.value, 0),
    child: child,
  ),
  child: GestureDetector(
    onTap: () { ... },
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) { ... }),
    ),
  ),
),
```

4. Add dispose:
```dart
@override
void dispose() {
  _shakeController.dispose();
  // ... rest of dispose ...
}
```

**Edge cases:**
- Rapid incorrect PIN entries: `_shakeController.forward(from: 0)` restarts animation
- PIN cleared by user manually: don't shake (only on `PinFailure`)
- Lockout state: no shake (PIN field disabled, no verification happens)
- Widget disposed during animation: `dispose()` cancels the controller

---

## Build Order & Dependencies

| Step | Item | File | Depends on |
|------|------|------|------------|
| 1 | UX-6: Pulsing mic | home_screen.dart | None — isolated widget change |
| 2 | UX-7: Typing indicator | home_screen.dart | Needs `sessionState` passed to `_ChatMessages` |
| 3 | UX-8: Date separators | home_screen.dart | Modifies `_ChatMessages` (shared with UX-7) |
| 4 | UX-22: PIN shake | auth_screen.dart | None — isolated widget change |

**Merge strategy:** Steps 1-3 all modify `home_screen.dart`'s `_ChatMessages` class. Apply all three together in one write to avoid conflicts.

## Animation Controllers Created

| Controller | Owner | Duration | Behavior |
|-----------|-------|----------|----------|
| `_pulseController` | `_MicButtonState` | 800ms | Repeating reverse, only during listening |
| `_controller` | `_TypingIndicatorState` | 1200ms | Infinite repeat for dot opacity |
| `_shakeController` | `_AuthScreenState` | 400ms | One-shot forward on PIN failure |
