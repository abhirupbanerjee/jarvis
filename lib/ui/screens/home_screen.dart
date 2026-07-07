// lib/ui/screens/home_screen.dart — Main Chat Screen
//
// Full chat interface with mic button, connection state indicator,
// tool call status, and dark J.A.R.V.I.S.-themed UI.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
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

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatData = ref.watch(chatProvider);
    final chat = ref.watch(chatProvider.notifier);

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
      body: Column(
        children: [
          // Tool status bar
          if (chatData.toolStatus.isNotEmpty) _ToolStatusBar(status: chatData.toolStatus),

          // Chat messages
          Expanded(
            child: chatData.messages.isEmpty && chatData.currentResponse.isEmpty
                ? _EmptyState()
                : _ChatMessages(
                    messages: chatData.messages,
                    currentResponse: chatData.currentResponse,
                    scrollController: _scrollController,
                  ),
          ),

          // Bottom input bar (text field + mic button)
          _InputBar(
            state: chatData.sessionState,
            onMicTap: chat.toggleListening,
            textController: _textController,
            onSendText: (text) {
              ref.read(chatProvider.notifier).sendTextPrompt(text);
            },
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
      ChatSessionState.speaking => (Colors.green, 'Speaking'),
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

// ── Empty State ──

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.mic_none,
            size: 64,
            color: theme.colorScheme.primary.withAlpha(80),
          ),
          const SizedBox(height: 16),
          Text(
            'Tap the mic to start',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try: "What time is it?" or "Search for the latest news"',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withAlpha(128),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chat Messages ──

class _ChatMessages extends StatelessWidget {
  final List<ChatMessage> messages;
  final String currentResponse;
  final ScrollController scrollController;

  const _ChatMessages({
    required this.messages,
    required this.currentResponse,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    // Auto-scroll to bottom on new messages
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: messages.length + (currentResponse.isNotEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        // Last item is the streaming response
        if (index == messages.length && currentResponse.isNotEmpty) {
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
        );
      },
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool isSystem;
  final bool isStreaming;

  const _ChatBubble({
    required this.text,
    this.isUser = false,
    this.isSystem = false,
    this.isStreaming = false,
  });

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

    return Align(
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
                  Flexible(child: Text(text, style: theme.textTheme.bodyMedium)),
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
    );
  }
}

// ── Input Bar (text field + mic button) ──

class _InputBar extends StatelessWidget {
  final ChatSessionState state;
  final VoidCallback onMicTap;
  final TextEditingController textController;
  final Function(String) onSendText;

  const _InputBar({
    required this.state,
    required this.onMicTap,
    required this.textController,
    required this.onSendText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isConnecting = state == ChatSessionState.connecting;

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
              controller: textController,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (text) {
                final trimmed = text.trim();
                if (trimmed.isNotEmpty) {
                  onSendText(trimmed);
                  textController.clear();
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          // Mic button
          _MicButton(state: state, onTap: onMicTap, isConnecting: isConnecting),
        ],
      ),
    );
  }
}

// ── Mic Button ──

class _MicButton extends StatelessWidget {
  final ChatSessionState state;
  final VoidCallback onTap;
  final bool isConnecting;

  const _MicButton({
    required this.state,
    required this.onTap,
    required this.isConnecting,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = state == ChatSessionState.listening;

    return GestureDetector(
      onTap: isConnecting ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? theme.colorScheme.error : theme.colorScheme.primary,
          boxShadow: [
            BoxShadow(
              color: (isActive ? theme.colorScheme.error : theme.colorScheme.primary)
                  .withAlpha(60),
              blurRadius: isActive ? 12 : 6,
              spreadRadius: isActive ? 3 : 1,
            ),
          ],
        ),
        child: isConnecting
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
                isActive ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: 22,
              ),
      ),
    );
  }
}

