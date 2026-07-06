// lib/providers/llm_provider_provider.dart — LLM Provider Riverpod Provider
//
// Provides the LlmProvider instance. Phase 1 returns GeminiLiveProvider.
// Future phases can switch based on configuration.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/gemini_live_provider.dart';
import 'config_provider.dart';
import 'llm_provider.dart';

/// The active LLM provider instance
final llmProviderProvider = Provider<LlmProvider>((ref) {
  final llmConfig = ref.watch(llmConfigProvider);
  return GeminiLiveProvider(llmConfig: llmConfig);
  // Future:
  // return switch (config.activeProvider) {
  //   LlmProviderType.gemini => GeminiLiveProvider(...),
  //   LlmProviderType.openai => OpenAILiveProvider(...),
  // };
});
