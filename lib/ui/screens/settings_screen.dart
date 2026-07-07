// lib/ui/screens/settings_screen.dart — Settings Screen
//
// Full settings with security, LLM config, memory, and about sections.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_config.dart';
import '../../config/llm_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../providers/database_provider.dart';
import '../widgets/change_pin_dialog.dart';
import 'memory_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // BUG-4 fix: cache futures to avoid recreating on every build.
  // ConsumerState allows ref access in initState.
  late Future<({bool available, bool enabled})> _biometricFuture;
  late Future<bool> _hasCustomPinFuture;
  bool _isTogglingBiometric = false;

  @override
  void initState() {
    super.initState();
    final authService = ref.read(authServiceProvider);
    _biometricFuture = () async {
      final available = await authService.isBiometricAvailable;
      final enabled = await authService.isBiometricEnabled;
      return (available: available, enabled: enabled);
    }();
    _hasCustomPinFuture = authService.hasCustomPin;
  }

  Future<void> _refreshPinFuture() async {
    final authService = ref.read(authServiceProvider);
    setState(() {
      _hasCustomPinFuture = authService.hasCustomPin;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authNotifier = ref.watch(authStateProvider.notifier);
    final authService = ref.watch(authServiceProvider);
    final llmConfig = ref.watch(llmConfigProvider);
    final db = ref.watch(databaseProvider);

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
          // ── SECURITY ──
          _SectionHeader(title: 'SECURITY', theme: theme),
          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
            child: FutureBuilder<({bool available, bool enabled})>(
              future: _biometricFuture,
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
                  onChanged: available && !_isTogglingBiometric
                      ? (value) async {
                          setState(() => _isTogglingBiometric = true);
                          await authNotifier.setBiometricEnabled(value);
                          if (mounted) {
                            setState(() => _isTogglingBiometric = false);
                          }
                        }
                      : null,
                  secondary: _isTogglingBiometric
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  activeTrackColor: theme.colorScheme.primary.withAlpha(128),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
            child: FutureBuilder<bool>(
              future: _hasCustomPinFuture,
              builder: (context, snapshot) {
                final hasCustom = snapshot.data ?? false;
                return ListTile(
                  leading: Icon(Icons.lock_reset, color: theme.colorScheme.primary),
                  title: const Text('Change PIN'),
                  subtitle: Text(
                    hasCustom ? 'PIN is set' : 'Using default PIN (0000)',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final changed = await showChangePinDialog(context, authService);
                    if (changed && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('PIN changed successfully')),
                      );
                      _refreshPinFuture();
                    }
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // ── LLM CONFIG ──
          _SectionHeader(title: 'LLM CONFIG', theme: theme),
          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.model_training, color: theme.colorScheme.primary),
                  title: const Text('Model'),
                  subtitle: Text('${llmConfig.modelId} · configured in .env'),
                ),
                ListTile(
                  leading: Icon(Icons.record_voice_over, color: theme.colorScheme.primary),
                  title: const Text('Voice'),
                  subtitle: Text('${llmConfig.voice} · configured in .env'),
                ),
                ListTile(
                  leading: Icon(Icons.thermostat, color: theme.colorScheme.primary),
                  title: const Text('Temperature'),
                  subtitle: Text('${llmConfig.temperature} · configured in .env'),
                ),
                ListTile(
                  leading: Icon(Icons.vpn_key, color: theme.colorScheme.primary),
                  title: const Text('Auth Mode'),
                  subtitle: Text(
                    '${llmConfig.useEphemeralTokens ? 'Ephemeral token' : 'API key'} · configured in .env',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── MEMORY ──
          _SectionHeader(title: 'MEMORY', theme: theme),
          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.memory, color: theme.colorScheme.primary),
                  title: const Text('View Stored Memories'),
                  subtitle: const Text('Review what J.A.R.V.I.S. remembers'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MemoryScreen(),
                      ),
                    );
                  },
                ),
                FutureBuilder<int>(
                  future: db.memoryCount,
                  builder: (context, snapshot) {
                    return ListTile(
                      leading: Icon(Icons.analytics_outlined, color: theme.colorScheme.primary),
                      title: const Text('Memory Count'),
                      trailing: Text(
                        '${snapshot.data ?? 0}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── CHAT ──
          _SectionHeader(title: 'CHAT', theme: theme),
          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.delete_sweep, color: theme.colorScheme.error),
                  title: const Text('Clear Chat History'),
                  subtitle: const Text('Remove all conversation messages'),
                  onTap: () => _confirmClearHistory(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── ABOUT ──
          _SectionHeader(title: 'ABOUT', theme: theme),
          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
            child: const Column(
              children: [
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('J.A.R.V.I.S. ${AppConfig.versionLabel}'),
                  subtitle: const Text('Prototype — Pixel 7 / Android 16+'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClearHistory(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Chat History'),
        content: const Text(
          'This will permanently delete all conversation messages. '
          'Memories will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final db = ref.read(databaseProvider);
              await db.clearHistory();
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chat history cleared')),
                );
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final ThemeData theme;

  const _SectionHeader({required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.primary,
        letterSpacing: 2,
      ),
    );
  }
}
