// lib/ui/screens/home_screen.dart — Main Chat Screen
//
// Full chat interface with mic button, connection state indicator,
// tool call status, error banner, scroll-to-bottom FAB, and dark J.A.R.V.I.S.-themed UI.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/chat_provider.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scrollController = ScrollController();
  final _textController = TextEditingController();
  bool _isNearBottom = true;

  static const _scrollThreshold = 80.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrollChanged);
  }

  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;
    final nearBottom = _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - _scrollThreshold;
    if (nearBottom != _isNearBottom) {
      setState(() => _isNearBottom = nearBottom);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _showClearConfirmDialog(BuildContext context, ChatNotifier chat) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear chat history?'),
        content: const Text(
          'This will remove all messages and start a fresh conversation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              chat.clearChat();
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrollChanged);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatData = ref.watch(chatProvider);
    final chat = ref.watch(chatProvider.notifier);

    final hasMessages =
        chatData.messages.isNotEmpty || chatData.currentResponse.isNotEmpty;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'J.A.R.V.I.S.',
          style: TextStyle(
            color: theme.colorScheme.primary,
            letterSpacing: 4,
            fontWeight: FontWeight.w300,
          ),
        ),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          // Connection status indicator
          _ConnectionIndicator(state: chatData.sessionState),
          // Help button — shows the welcome guide anytime
          IconButton(
            icon: Icon(
              Icons.help_outline,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            tooltip: 'How to use JARVIS',
            onPressed: () => _showWelcomeGuide(context, chat),
          ),
          // Clear chat button (only visible when there are messages)
          if (hasMessages)
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              tooltip: 'Clear chat',
              onPressed: () => _showClearConfirmDialog(context, chat),
            ),
          // Settings button
          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Tool status bar
              if (chatData.toolStatus.isNotEmpty)
                _ToolStatusBar(status: chatData.toolStatus),

              // Error banner
              if (chatData.sessionState == ChatSessionState.error &&
                  chatData.lastError.isNotEmpty)
                _ErrorBanner(
                  message: chatData.lastError,
                  onRetry: chat.toggleListening,
                ),

              // Chat messages
              Expanded(
                child: hasMessages
                    ? _ChatMessages(
                        messages: chatData.messages,
                        currentResponse: chatData.currentResponse,
                        scrollController: _scrollController,
                        isNearBottom: _isNearBottom,
                        sessionState: chatData.sessionState,
                      )
                    : _EmptyState(chat: chat),
              ),

              // Bottom input bar (text field + mic button)
              _InputBar(
                state: chatData.sessionState,
                onMicTap: chat.toggleListening,
                onStopTap: chat.stopResponding,
                textController: _textController,
                onSendText: (text) {
                  ref.read(chatProvider.notifier).sendTextPrompt(text);
                },
              ),
            ],
          ),

          // Scroll-to-bottom FAB
          if (hasMessages && !_isNearBottom)
            Positioned(
              right: 16,
              bottom: 80,
              child: _ScrollToBottomButton(onTap: _scrollToBottom),
            ),
        ],
      ),
    );
  }
}

// ── Connection Indicator ──

class _ConnectionIndicator extends StatelessWidget {
  final ChatSessionState state;
  const _ConnectionIndicator({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, label) = switch (state) {
      ChatSessionState.idle => (theme.colorScheme.onSurfaceVariant, 'Idle'),
      ChatSessionState.connecting => (Colors.orange, 'Connecting...'),
      ChatSessionState.listening => (Colors.green, 'Listening'),
      ChatSessionState.thinking => (theme.colorScheme.primary, 'Thinking...'),
      ChatSessionState.speaking => (Colors.teal, 'Speaking'),
      ChatSessionState.error => (theme.colorScheme.error, 'Error'),
    };

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withAlpha(128),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tool Status Bar ──

class _ToolStatusBar extends StatelessWidget {
  final String status;
  const _ToolStatusBar({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.primaryContainer.withAlpha(60),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error Banner ──

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.errorContainer.withAlpha(120),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scroll-to-Bottom Button ──

class _ScrollToBottomButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ScrollToBottomButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FloatingActionButton.small(
      onPressed: onTap,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.keyboard_arrow_down,
        color: theme.colorScheme.primary,
      ),
    );
  }
}

// ── Empty State ──
// Shows a welcome guide for new users. The same guide is reachable via the
// help icon in the app bar.

class _EmptyState extends StatelessWidget {
  final ChatNotifier chat;

  const _EmptyState({required this.chat});

  @override
  Widget build(BuildContext context) {
    return _WelcomeGuide(
      chat: chat,
      showTitle: true,
      compact: false,
    );
  }
}

// ── Welcome Guide ──
// Reusable onboarding content used in both the empty state and the help dialog.

class _WelcomeGuide extends StatelessWidget {
  final ChatNotifier chat;
  final bool showTitle;
  final bool compact;

  const _WelcomeGuide({
    required this.chat,
    this.showTitle = true,
    this.compact = false,
  });

  static const _examplePrompts = [
    'What time is it?',
    'Search for the latest news',
    'Set a timer for 5 minutes',
    'What is the weather today?',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 24, vertical: compact ? 0 : 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showTitle) ...[
            Icon(
              Icons.mic_none,
              size: 56,
              color: theme.colorScheme.primary.withAlpha(80),
            ),
            const SizedBox(height: 12),
            Text(
              'How to talk to J.A.R.V.I.S.',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
          ],
          _GuideStep(
            number: 1,
            icon: Icons.mic,
            title: 'Tap the mic button',
            description: 'JARVIS starts listening. Wait for the "Speak now" hint.',
          ),
          const SizedBox(height: 12),
          _GuideStep(
            number: 2,
            icon: Icons.record_voice_over,
            title: 'Speak your request',
            description: 'Ask a question or give a command in natural language.',
          ),
          const SizedBox(height: 12),
          _GuideStep(
            number: 3,
            icon: Icons.volume_up,
            title: 'Listen to the response',
            description: 'JARVIS speaks back. Tap the red stop button anytime to interrupt.',
          ),
          const SizedBox(height: 12),
          _GuideStep(
            number: 4,
            icon: Icons.mic,
            title: 'Tap the mic again to continue',
            description: 'After each response, the mic turns off. Tap to start a new turn.',
          ),
          const SizedBox(height: 24),
          Text(
            'Try saying:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _examplePrompts.map((prompt) {
              return ActionChip(
                avatar: Icon(
                  Icons.chat_bubble_outline,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                label: Text(prompt),
                labelStyle: theme.textTheme.bodySmall,
                backgroundColor: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                side: BorderSide.none,
                onPressed: () => chat.sendTextPrompt(prompt),
              );
            }).toList(),
          ),
          if (!compact) ...[
            const SizedBox(height: 24),
            Text(
              'You can also type a message when the session is idle.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withAlpha(128),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  final int number;
  final IconData icon;
  final String title;
  final String description;

  const _GuideStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary.withAlpha(40),
          ),
          child: Center(
            child: Text(
              '$number',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

void _showWelcomeGuide(BuildContext context, ChatNotifier chat) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: const Text('How to use J.A.R.V.I.S.'),
      content: SizedBox(
        width: double.maxFinite,
        child: _WelcomeGuide(
          chat: chat,
          showTitle: false,
          compact: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

// ── Chat Messages ──

class _ChatMessages extends StatelessWidget {
  final List<ChatMessage> messages;
  final String currentResponse;
  final ScrollController scrollController;
  final bool isNearBottom;
  final ChatSessionState sessionState;

  const _ChatMessages({
    required this.messages,
    required this.currentResponse,
    required this.scrollController,
    required this.isNearBottom,
    required this.sessionState,
  });

  @override
  Widget build(BuildContext context) {
    // Only auto-scroll when user is already near the bottom (BUG-1 fix)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients && isNearBottom) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });

    // UX-7: show typing indicator when thinking but no text yet
    final showTyping = sessionState == ChatSessionState.thinking &&
        currentResponse.isEmpty;
    final streamingExtra = currentResponse.isNotEmpty ? 1 : 0;
    final typingExtra = showTyping ? 1 : 0;
    final lastMessageIndex = messages.length;

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: messages.length + streamingExtra + typingExtra,
      itemBuilder: (context, index) {
        // Typing indicator at the very end when thinking with no text
        if (showTyping && index == messages.length) {
          return const _TypingIndicator();
        }

        // Last item is the streaming response
        if (index == lastMessageIndex && currentResponse.isNotEmpty) {
          return _ChatBubble(
            text: currentResponse,
            isUser: false,
            isStreaming: true,
          );
        }

        final msg = messages[index];
        return _ChatBubble(
          text: msg.text,
          isUser: msg.isUser,
          isSystem: msg.isSystem,
          timestamp: msg.timestamp,
        );
      },
    );
  }
}

// ── Typing Indicator (UX-7) ──

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

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
            return AnimatedBuilder(
              animation: _controller,
              builder: (_, child) {
                final delay = i * 0.2;
                final t = (_controller.value - delay).clamp(0.0, 1.0);
                final opacity = (t < 0.5 ? t * 2 : 2 - t * 2).clamp(0.2, 1.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary
                          .withAlpha((opacity * 180).round()),
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

class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool isSystem;
  final bool isStreaming;
  final DateTime? timestamp;

  const _ChatBubble({
    required this.text,
    this.isUser = false,
    this.isSystem = false,
    this.isStreaming = false,
    this.timestamp,
  });

  void _copyText(BuildContext context) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withAlpha(128),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    // UX-1: format timestamp
    final timeLabel = timestamp != null
        ? DateFormat('h:mm a').format(timestamp!)
        : null;

    final bubble = GestureDetector(
      // UX-2: long-press to copy
      onLongPress: () => _copyText(context),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          decoration: BoxDecoration(
            color: isUser
                ? theme.colorScheme.primary.withAlpha(40)
                : theme.colorScheme.surfaceContainerHighest.withAlpha(80),
            borderRadius: BorderRadius.circular(16).copyWith(
              bottomRight: isUser ? const Radius.circular(4) : null,
              bottomLeft: isUser ? null : const Radius.circular(4),
            ),
          ),
          child: isStreaming
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                        child:
                            Text(text, style: theme.textTheme.bodyMedium)),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                )
              : Text(text, style: theme.textTheme.bodyMedium),
        ),
      ),
    );

    // Show timestamp below bubble for non-streaming messages
    if (timeLabel != null && !isStreaming) {
      return Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          bubble,
          Padding(
            padding: EdgeInsets.only(
              left: isUser ? 0 : 14,
              right: isUser ? 14 : 0,
              top: 2,
            ),
            child: Text(
              timeLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
                fontSize: 10,
              ),
            ),
          ),
        ],
      );
    }

    return bubble;
  }
}

// ── Input Bar (text field + send button + mic button) ──

class _InputBar extends StatefulWidget {
  final ChatSessionState state;
  final VoidCallback onMicTap;
  final VoidCallback onStopTap;
  final TextEditingController textController;
  final Function(String) onSendText;

  const _InputBar({
    required this.state,
    required this.onMicTap,
    required this.onStopTap,
    required this.textController,
    required this.onSendText,
  });

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final hasText = widget.textController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _send() {
    final trimmed = widget.textController.text.trim();
    if (trimmed.isNotEmpty) {
      widget.onSendText(trimmed);
      widget.textController.clear();
      HapticFeedback.lightImpact();
    }
  }

  String _hintForState(ChatSessionState state) {
    return switch (state) {
      ChatSessionState.idle || ChatSessionState.error => 'Type a message...',
      ChatSessionState.connecting => 'Connecting...',
      ChatSessionState.listening => 'Speak now — I\'m listening...',
      ChatSessionState.thinking => 'J.A.R.V.I.S. is thinking...',
      ChatSessionState.speaking => 'J.A.R.V.I.S. is speaking...',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    final isConnecting = state == ChatSessionState.connecting;
    // BUG-2 fix: disable text input during active sessions
    final textEnabled =
        state == ChatSessionState.idle || state == ChatSessionState.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
      ),
      child: Row(
        children: [
          // Text input field
          Expanded(
            child: TextField(
              controller: widget.textController,
              enabled: textEnabled,
              style: theme.textTheme.bodyMedium,
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: _hintForState(state),
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
                ),
                filled: true,
                fillColor:
                    theme.colorScheme.surfaceContainerHighest.withAlpha(60),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: textEnabled ? (_) => _send() : null,
            ),
          ),
          const SizedBox(width: 8),
          // BUG-3 fix: send button when text is entered
          if (_hasText && textEnabled)
            _SendButton(onTap: _send),
          // Stop button when JARVIS is thinking or speaking
          if (state == ChatSessionState.thinking ||
              state == ChatSessionState.speaking)
            _StopButton(onTap: widget.onStopTap)
          else
            _MicButton(state: state, onTap: widget.onMicTap, isConnecting: isConnecting),
        ],
      ),
    );
  }
}

// ── Send Button ──

class _SendButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SendButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary,
          ),
          child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

// ── Stop Button ──

class _StopButton extends StatelessWidget {
  final VoidCallback onTap;
  const _StopButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.redAccent,
        ),
        child: const Icon(
          Icons.stop_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}

// ── Mic Button (UX-6: pulsing animation during listening) ──
//
// Tap-to-talk model:
//   - idle: mic icon → tap to start session
//   - listening: pulsing mic icon → JARVIS is listening
//   - thinking: hourglass icon → JARVIS is processing
//   - speaking: speaker icon → JARVIS is talking; tap to interrupt/end

class _MicButton extends StatefulWidget {
  final ChatSessionState state;
  final VoidCallback onTap;
  final bool isConnecting;

  const _MicButton({
    required this.state,
    required this.onTap,
    required this.isConnecting,
  });

  @override
  State<_MicButton> createState() => _MicButtonState();
}

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
    _syncPulse(widget.state);
  }

  void _syncPulse(ChatSessionState state) {
    if (state == ChatSessionState.listening) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
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
    final theme = Theme.of(context);
    final state = widget.state;
    // Active = session in progress (listening/thinking/speaking).
    // Tapping during these states ends the session.
    final isActive = state == ChatSessionState.listening ||
        state == ChatSessionState.thinking ||
        state == ChatSessionState.speaking;

    // Choose icon + color per state to communicate the continuous
    // conversation model (like Gemini Live):
    //  - idle: mic icon (tap to start)
    //  - listening: mic icon (pulsing) — JARVIS is listening continuously
    //  - thinking: hourglass — JARVIS is processing
    //  - speaking: speaker icon — JARVIS is talking (tap to interrupt/end)
    final (icon, bgColor) = switch (state) {
      ChatSessionState.listening => (Icons.mic, theme.colorScheme.primary),
      ChatSessionState.thinking => (Icons.hourglass_top, theme.colorScheme.primary),
      ChatSessionState.speaking => (Icons.volume_up, Colors.teal),
      _ => (Icons.mic, theme.colorScheme.primary),
    };

    final button = GestureDetector(
      onTap: widget.isConnecting
          ? null
          : () {
              HapticFeedback.mediumImpact();
              widget.onTap();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bgColor,
          boxShadow: [
            BoxShadow(
              color: bgColor.withAlpha(60),
              blurRadius: isActive ? 12 : 6,
              spreadRadius: isActive ? 3 : 1,
            ),
          ],
        ),
        child: widget.isConnecting
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              )
            : Icon(
                icon,
                color: Colors.white,
                size: 22,
              ),
      ),
    );

    // UX-6: pulsing scale animation during listening state
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) => Transform.scale(
        scale: _pulseAnim.value,
        child: child,
      ),
      child: button,
    );
  }
}