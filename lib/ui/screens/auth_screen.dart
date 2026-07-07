// lib/ui/screens/auth_screen.dart — Dual Biometric + PIN Authentication Screen
//
// Shows both a biometric unlock button (if hardware available and user enabled)
// and a 4-digit PIN entry. User chooses their preferred method. PIN defaults
// to "0000" and can be changed via dialog (post-auth only — moved to settings).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../providers/auth_provider.dart';
import '../widgets/change_pin_dialog.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with SingleTickerProviderStateMixin {
  final _pinController = TextEditingController();
  final _pinFocusNode = FocusNode();
  final _pinDigits = List.filled(4, '');
  int _previousPinLength = 0;

  bool _isBiometricAvailable = false;
  bool _isBiometricEnabled = false;
  List<BiometricType> _biometricTypes = [];
  bool _isAuthenticating = false;
  String? _errorMessage;
  bool _pinLockedOut = false;
  Timer? _lockoutTimer;
  Duration _lockoutRemaining = Duration.zero;
  bool _autoPrompted = false;

  // UX-22: PIN dot shake animation
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
      TweenSequenceItem(tween: Tween<double>(begin: 0, end: -8), weight: 1),
      TweenSequenceItem(tween: Tween<double>(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: 8, end: -4), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: -4, end: 4), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: 4, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeInOut,
    ));
    _checkBiometricAvailability();
    _pinController.addListener(_onPinChanged);
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _pinController.removeListener(_onPinChanged);
    _pinController.dispose();
    _pinFocusNode.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkBiometricAvailability() async {
    final authService = ref.read(authServiceProvider);
    final authNotifier = ref.read(authStateProvider.notifier);

    final available = await authNotifier.isBiometricOptionAvailable;
    if (!mounted) return;

    final enabled = await authService.isBiometricEnabled;
    final types = await authService.getAvailableBiometrics();

    setState(() {
      _isBiometricAvailable = available;
      _isBiometricEnabled = enabled;
      _biometricTypes = types;
    });

    // UX-21: Auto-prompt biometric on screen appear if available and enabled
    if (_isBiometricAvailable && _isBiometricEnabled && !_autoPrompted) {
      _autoPrompted = true;
      // Short delay so the UI renders before system biometric dialog
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && !_isAuthenticating && _pinController.text.isEmpty) {
          _attemptBiometric();
        }
      });
    }
  }

  void _onPinChanged() {
    final text = _pinController.text;
    final newLength = text.length;

    // UX-24: haptic feedback on each digit entry
    if (newLength > _previousPinLength && newLength <= 4) {
      HapticFeedback.selectionClick();
    }
    _previousPinLength = newLength;

    setState(() {
      for (var i = 0; i < 4; i++) {
        _pinDigits[i] = i < text.length ? '•' : '';
      }
    });

    if (text.length == 4 && !_pinLockedOut) {
      _verifyPin(text);
    }
  }

  Future<void> _verifyPin(String pin) async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    final authNotifier = ref.read(authStateProvider.notifier);
    final result = await authNotifier.verifyPin(pin);

    if (!mounted) return;

    switch (result) {
      case PinSuccess():
        // AuthGate will rebuild and show HomeScreen
        break;
      case PinFailure(:final remainingAttempts):
        _pinController.clear();
        _previousPinLength = 0;
        setState(() {
          _isAuthenticating = false;
          _errorMessage = 'Incorrect PIN — $remainingAttempts attempts remaining';
        });
        _shakeController.forward(from: 0); // UX-22: shake on wrong PIN
        _pinFocusNode.requestFocus();
      case PinLockedOut(:final remaining):
        _pinController.clear();
        _previousPinLength = 0;
        setState(() {
          _isAuthenticating = false;
          _pinLockedOut = true;
          _lockoutRemaining = remaining;
          _errorMessage = 'Too many attempts. Try again in ${_formatDuration(remaining)}';
        });
        _startLockoutTimer(remaining);
    }
  }

  void _startLockoutTimer(Duration remaining) {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final newRemaining = _lockoutRemaining - const Duration(seconds: 1);
      if (newRemaining <= Duration.zero) {
        _lockoutTimer?.cancel();
        if (mounted) {
          setState(() {
            _pinLockedOut = false;
            _lockoutRemaining = Duration.zero;
            _errorMessage = null;
          });
        }
      } else {
        setState(() {
          _lockoutRemaining = newRemaining;
          _errorMessage = 'Too many attempts. Try again in ${_formatDuration(newRemaining)}';
        });
      }
    });
  }

  Future<void> _attemptBiometric() async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    final authNotifier = ref.read(authStateProvider.notifier);
    final success = await authNotifier.authenticateWithBiometric();

    if (!mounted) return;

    if (!success) {
      setState(() {
        _isAuthenticating = false;
        _errorMessage = 'Biometric authentication failed. Try again or use PIN.';
      });
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  IconData _biometricIcon() {
    if (_biometricTypes.contains(BiometricType.face)) return Icons.face;
    if (_biometricTypes.contains(BiometricType.iris)) return Icons.remove_red_eye;
    return Icons.fingerprint;
  }

  String _biometricLabel() {
    if (_biometricTypes.contains(BiometricType.face)) return 'Face Unlock';
    if (_biometricTypes.contains(BiometricType.iris)) return 'Iris Scan';
    return 'Fingerprint';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Lock icon
                Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  'J.A.R.V.I.S.',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    letterSpacing: 8,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Authentication required',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 40),

                // ── PIN Entry ──
                Text(
                  'Enter PIN',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),

                // Hidden PIN text field (captures input)
                SizedBox(
                  width: 0,
                  height: 0,
                  child: TextField(
                    controller: _pinController,
                    focusNode: _pinFocusNode,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: false, // We render our own dots
                    enableInteractiveSelection: false,
                    enabled: !_pinLockedOut,
                    autofocus: true,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: const InputDecoration(
                      counterText: '',
                    ),
                    style: const TextStyle(fontSize: 1),
                    cursorColor: Colors.transparent,
                  ),
                ),

                // Visual PIN dots (UX-22: wrapped with shake animation)
                AnimatedBuilder(
                  animation: _shakeAnim,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(_shakeAnim.value, 0),
                    child: child,
                  ),
                  child: GestureDetector(
                    onTap: () {
                      if (!_pinLockedOut) _pinFocusNode.requestFocus();
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (i) {
                        final filled = _pinDigits[i].isNotEmpty;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 48,
                          height: 48,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: filled
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant,
                              width: 1.5,
                            ),
                            color: filled
                                ? theme.colorScheme.primary.withAlpha(30)
                                : Colors.transparent,
                          ),
                          child: Center(
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: filled
                                    ? theme.colorScheme.primary
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // PIN error / lockout message
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _pinLockedOut
                            ? Colors.orange
                            : theme.colorScheme.error,
                      ),
                    ),
                  ),

                const SizedBox(height: 8),

                // ── Divider with "OR" ──
                // BUG-9 fix: check both hardware availability AND user preference
                if (_isBiometricAvailable && _isBiometricEnabled) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Divider(
                          color: theme.colorScheme.outlineVariant.withAlpha(80),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'OR',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Divider(
                          color: theme.colorScheme.outlineVariant.withAlpha(80),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Biometric Button ──
                  GestureDetector(
                    onTap: _isAuthenticating ? null : _attemptBiometric,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isAuthenticating
                              ? theme.colorScheme.primary.withAlpha(128)
                              : theme.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      child: _isAuthenticating
                          ? Center(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            )
                          : Icon(
                              _biometricIcon(),
                              size: 36,
                              color: theme.colorScheme.primary,
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isAuthenticating ? 'Authenticating...' : _biometricLabel(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                // UX-25: Change PIN removed from lock screen (available in settings post-auth)
              ],
            ),
          ),
        ),
      ),
    );
  }
}
