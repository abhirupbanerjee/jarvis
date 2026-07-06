// lib/config/llm_config.dart — LLM Configuration from .env
//
// Centralizes all LLM-related configuration, loaded from environment variables
// via flutter_dotenv. Configurable model ID, temperature, and voice.
//
// Supports two auth modes:
// 1. Ephemeral tokens (production): Set GEMINI_TOKEN_ENDPOINT and TOKEN_SHARED_SECRET
//    The real API key lives only on the backend server.
// 2. Direct API key (development): Set GEMINI_API_KEY directly.
//    Only for local testing — never ship to production.

import 'package:flutter_dotenv/flutter_dotenv.dart';

class LlmConfig {
  final String modelId;
  final double temperature;
  final String voice;
  final String apiKey;
  final String tokenEndpoint;
  final String tokenAuthSecret;

  const LlmConfig({
    required this.modelId,
    required this.temperature,
    required this.voice,
    required this.apiKey,
    this.tokenEndpoint = '',
    this.tokenAuthSecret = '',
  });

  /// Create config from environment variables (.env file)
  factory LlmConfig.fromEnv() {
    return LlmConfig(
      modelId: dotenv.env['GEMINI_MODEL_ID'] ?? 'gemini-2.5-flash-native-audio-latest',
      temperature: double.tryParse(dotenv.env['GEMINI_TEMPERATURE'] ?? '0.7') ?? 0.7,
      voice: dotenv.env['GEMINI_VOICE'] ?? 'Puck',
      apiKey: dotenv.env['GEMINI_API_KEY'] ?? '',
      tokenEndpoint: dotenv.env['GEMINI_TOKEN_ENDPOINT'] ?? '',
      tokenAuthSecret: dotenv.env['TOKEN_SHARED_SECRET'] ?? '',
    );
  }

  /// Whether to use ephemeral tokens fetched from a backend
  bool get useEphemeralTokens =>
      tokenEndpoint.isNotEmpty && tokenEndpoint.startsWith('http');

  /// Validate that required configuration is present
  bool get isValid {
    if (useEphemeralTokens) {
      return tokenAuthSecret.isNotEmpty;
    }
    return apiKey.isNotEmpty && apiKey != 'PLACEHOLDER_SET_YOUR_KEY_HERE';
  }

  @override
  String toString() => 'LlmConfig(modelId: $modelId, temperature: $temperature, '
      'voice: $voice, authMode: ${useEphemeralTokens ? "ephemeral" : "apiKey"})';
}
