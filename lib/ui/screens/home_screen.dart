// lib/ui/screens/home_screen.dart — Main Chat Screen
//
// Full chat interface with mic button, connection state indicator,
// tool call status, and dark J.A.R.V.I.S.-themed UI.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scrollController = ScrollController();

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
                  builder: (_) => const _SettingsScreen(),
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

          // Bottom mic bar
          _MicBar(
            state: chatData.sessionState,
            onTap: chat.toggleListening,
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

// ── Mic Button Bar ──

class _MicBar extends StatelessWidget {
  final ChatSessionState state;
  final VoidCallback onTap;

  const _MicBar({required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = state == ChatSessionState.listening;
    final isConnecting = state == ChatSessionState.connecting;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: isConnecting ? null : onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
                boxShadow: [
                  BoxShadow(
                    color: (isActive
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary)
                        .withAlpha(60),
                    blurRadius: isActive ? 16 : 8,
                    spreadRadius: isActive ? 4 : 1,
                  ),
                ],
              ),
              child: isConnecting
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : Icon(
                      isActive ? Icons.stop : Icons.mic,
                      color: Colors.white,
                      size: 28,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Settings Screen (inline for now) ──

class _SettingsScreen extends ConsumerStatefulWidget {
  const _SettingsScreen();

  @override
  ConsumerState<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<_SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authNotifier = ref.watch(authStateProvider.notifier);
    final authService = ref.watch(authServiceProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: TextStyle(
            color: theme.colorScheme.primary,
            letterSpacing: 2,
            fontWeight: FontWeight.w300,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Biometric section
          Text(
            'SECURITY',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
            child: FutureBuilder<({bool available, bool enabled})>(
              future: () async {
                final available = await authService.isBiometricAvailable;
                final enabled = await authService.isBiometricEnabled;
                return (available: available, enabled: enabled);
              }(),
              builder: (context, snapshot) {
                final data = snapshot.data;
                final available = data?.available ?? false;
                final enabled = data?.enabled ?? false;
                return SwitchListTile(
                  title: const Text('Biometric Lock'),
                  subtitle: Text(
                    available
                        ? 'Require fingerprint or face to unlock'
                        : 'No biometric hardware detected',
                  ),
                  value: enabled && available,
                  onChanged: available
                      ? (value) => authNotifier.setBiometricEnabled(value)
                      : null,
                  activeTrackColor: theme.colorScheme.primary.withAlpha(128),
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // Memory section
          Text(
            'MEMORY',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
            child: ListTile(
              leading: Icon(Icons.memory, color: theme.colorScheme.primary),
              title: const Text('View Stored Memories'),
              subtitle: const Text('Review what J.A.R.V.I.S. remembers'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // TODO: Memory viewer screen
              },
            ),
          ),
          const SizedBox(height: 24),

          // About section
          Text(
            'ABOUT',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
            child: const Column(
              children: [
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('J.A.R.V.I.S. Phase 1'),
                  subtitle: Text('Prototype — Pixel 7 / Android 16+'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
