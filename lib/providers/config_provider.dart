// lib/providers/config_provider.dart — Configuration Riverpod Providers

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/llm_config.dart';

/// LlmConfig loaded from .env at app startup
final llmConfigProvider = Provider<LlmConfig>((ref) {
  return LlmConfig.fromEnv();
});
