// lib/services/auth_service.dart — App-Lock Service (Biometric + PIN)
//
// Provides dual-unlock: biometric (fingerprint/face) and 4-digit PIN.
// PIN defaults to "0000" and can be changed by the user.
// Both credentials are stored in platform secure storage.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:logging/logging.dart';

final _log = Logger('AuthService');

class AuthService {
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const _biometricEnabledKey = 'biometric_enabled';
  static const _isFirstLaunchKey = 'is_first_launch';
  static const _pinKey = 'user_pin';
  static const _defaultPin = '0000';

  /// Check if biometrics are available on this device
  Future<bool> get isBiometricAvailable async {
    try {
      return await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
    } catch (e) {
      _log.warning('Biometric availability check failed: $e');
      return false;
    }
  }

  /// Get list of available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      _log.warning('Failed to get biometric types: $e');
      return [];
    }
  }

  /// Authenticate with biometric (fingerprint/face)
  /// Returns true if authenticated or if biometric is not available
  Future<bool> authenticate() async {
    if (!await isBiometricAvailable) {
      _log.info('Biometric not available, skipping authentication');
      return true;
    }

    if (!await isBiometricEnabled) {
      _log.info('Biometric disabled by user, skipping authentication');
      return true;
    }

    try {
      return await _localAuth.authenticate(
        localizedReason: 'Authenticate to unlock J.A.R.V.I.S.',
        options: const AuthenticationOptions(
          stickyAuth: true, // Survives app backgrounding
          biometricOnly: false, // Allow PIN/pattern fallback on devices without biometric HW
        ),
      );
    } catch (e) {
      _log.severe('Biometric authentication failed: $e');
      return false;
    }
  }

  /// Toggle biometric on/off (persisted in secure storage)
  Future<void> setBiometricEnabled(bool enabled) async {
    await _secureStorage.write(
      key: _biometricEnabledKey,
      value: enabled.toString(),
    );
    _log.info('Biometric ${enabled ? "enabled" : "disabled"}');
  }

  /// Check if biometric authentication is enabled by user
  Future<bool> get isBiometricEnabled async {
    final value = await _secureStorage.read(key: _biometricEnabledKey);
    // Default: enabled if hardware supports it
    if (value == null) {
      final available = await isBiometricAvailable;
      return available; // Enable by default if hardware available
    }
    return value == 'true';
  }

  /// Check if this is the first app launch
  Future<bool> get isFirstLaunch async {
    final value = await _secureStorage.read(key: _isFirstLaunchKey);
    return value == null;
  }

  /// Mark first launch as complete
  Future<void> completeFirstLaunch() async {
    await _secureStorage.write(
      key: _isFirstLaunchKey,
      value: 'false',
    );
  }

  // ── PIN Management ──

  /// Get the stored PIN (returns "0000" if never set)
  Future<String> getPin() async {
    return await _secureStorage.read(key: _pinKey) ?? _defaultPin;
  }

  /// Set a new 4-digit PIN
  Future<void> setPin(String newPin) async {
    await _secureStorage.write(key: _pinKey, value: newPin);
    _log.info('PIN updated');
  }

  /// Verify a PIN attempt against the stored PIN
  Future<bool> verifyPin(String pin) async {
    final stored = await getPin();
    return pin == stored;
  }

  /// Whether the user has changed the PIN from the default
  Future<bool> get hasCustomPin async {
    final stored = await _secureStorage.read(key: _pinKey);
    return stored != null && stored != _defaultPin;
  }
}
