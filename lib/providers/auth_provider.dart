// lib/providers/auth_provider.dart — Auth State Management (Biometric + PIN)

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';

/// Authentication states for the UI layer
enum AuthState {
  /// Initial state, checking availability
  checking,

  /// First launch — skip auth, show app directly
  firstLaunch,

  /// Lock screen shown — user must use biometric or PIN
  locked,

  /// User is authenticated, proceed to app
  authenticated,
}

/// Max failed PIN attempts before temporary lockout
const _maxPinAttempts = 5;
const _pinLockoutDuration = Duration(seconds: 30);

/// Auth notifier that manages the dual biometric + PIN lock flow
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;

  int _pinAttempts = 0;
  DateTime? _pinLockoutUntil;

  AuthNotifier(this._authService) : super(AuthState.checking) {
    _initialize();
  }

  Future<void> _initialize() async {
    // Check if first launch
    final isFirstLaunch = await _authService.isFirstLaunch;
    if (isFirstLaunch) {
      await _authService.completeFirstLaunch();
      // Ensure default PIN is set on first launch
      await _authService.setPin('0000');
      state = AuthState.firstLaunch;
      return;
    }

    // Always lock — user can choose biometric or PIN
    state = AuthState.locked;
  }

  /// Attempt biometric authentication
  Future<bool> authenticateWithBiometric() async {
    if (!await _authService.isBiometricAvailable) return false;
    if (!await _authService.isBiometricEnabled) return false;

    final success = await _authService.authenticate();
    if (success) {
      state = AuthState.authenticated;
      _pinAttempts = 0;
    }
    return success;
  }

  /// Verify a 4-digit PIN attempt
  Future<PinResult> verifyPin(String pin) async {
    // Check lockout
    if (_pinLockoutUntil != null) {
      if (DateTime.now().isBefore(_pinLockoutUntil!)) {
        final remaining = _pinLockoutUntil!.difference(DateTime.now());
        return PinLockedOut(remaining);
      }
      _pinLockoutUntil = null;
      _pinAttempts = 0;
    }

    final valid = await _authService.verifyPin(pin);
    if (valid) {
      state = AuthState.authenticated;
      _pinAttempts = 0;
      return const PinSuccess();
    }

    _pinAttempts++;
    if (_pinAttempts >= _maxPinAttempts) {
      _pinLockoutUntil = DateTime.now().add(_pinLockoutDuration);
      return PinLockedOut(_pinLockoutDuration);
    }

    return PinFailure(_maxPinAttempts - _pinAttempts);
  }

  /// Toggle biometric on/off from settings
  Future<void> setBiometricEnabled(bool enabled) async {
    await _authService.setBiometricEnabled(enabled);
    // Re-check: if we're authenticated, stay authenticated
    if (state == AuthState.authenticated) return;
    state = AuthState.locked;
  }

  /// Check if biometric option should be shown on lock screen
  Future<bool> get isBiometricOptionAvailable async {
    return await _authService.isBiometricAvailable &&
        await _authService.isBiometricEnabled;
  }
}

/// Result of a PIN verification attempt
sealed class PinResult {
  const PinResult();
}

class PinSuccess extends PinResult {
  const PinSuccess();
}

class PinFailure extends PinResult {
  final int remainingAttempts;
  const PinFailure(this.remainingAttempts);
}

class PinLockedOut extends PinResult {
  final Duration remaining;
  const PinLockedOut(this.remaining);
}

/// Riverpod provider for the auth service (singleton)
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// Riverpod provider for auth state
final authStateProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthNotifier(authService);
});
