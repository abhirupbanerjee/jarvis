// lib/main.dart — J.A.R.V.I.S. Phase 1 Entry Point

import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:logging/logging.dart';

import 'providers/auth_provider.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Setup structured logging ──
  // Use verbose logs in debug builds; limit to warnings+ in release
  // to avoid thousands of debugPrint calls per voice session.
  Logger.root.level = kDebugMode ? Level.ALL : Level.WARNING;
  Logger.root.onRecord.listen((record) {
    final time = record.time.toIso8601String().substring(11, 23);
    final level = record.level.name.padRight(7);
    final name = record.loggerName.padRight(20);
    debugPrint('[$time] $level $name ${record.message}');
    if (record.error != null) {
      debugPrint('[$time] $level $name   error: ${record.error}');
    }
    if (record.stackTrace != null) {
      debugPrint('[$time] $level $name   stack: ${record.stackTrace}');
    }
  });

  // Load environment configuration from .env
  try {
    await dotenv.load();
  } catch (e) {
    debugPrint('⚠️ Failed to load .env: $e');
  }

  // Initialize alarm service for in-app alarm tools
  await Alarm.init();

  // Register home screen widget group
  HomeWidget.setAppGroupId('com.jarvis.jarvis');

  runApp(
    const ProviderScope(
      child: JarvisApp(),
    ),
  );
}

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'J.A.R.V.I.S.',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF00BCD4), // Cyan accent — JARVIS-style
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF00BCD4),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.dark,
      home: const AuthGate(),
    );
  }
}

/// Routes the user based on auth state:
/// - checking → splash/loading
/// - locked → biometric prompt
/// - firstLaunch / authenticated / skipped → main app
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return switch (authState) {
      AuthState.checking => const _SplashScreen(),
      AuthState.locked => const AuthScreen(),
      _ => const HomeScreen(),
    };
  }
}

/// Simple splash shown while checking auth state
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.circle,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'J.A.R.V.I.S.',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 8,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
