// lib/providers/llm_provider.dart — LLM Provider Abstract Interface
//
// Defines the contract for any LLM provider (Gemini, OpenAI, Claude, local).
// Phase 1 implements GeminiLiveProvider. Future providers implement this interface.

import 'dart:async';

/// Connection states for the LLM provider
enum ConnectionState { disconnected, connecting, connected, error }

/// Represents a function/tool call request from the LLM
class FunctionCall {
  final String id;
  final String name;
  final Map<String, dynamic> args;

  const FunctionCall({
    required this.id,
    required this.name,
    required this.args,
  });

  @override
  String toString() => 'FunctionCall(id: $id, name: $name, args: $args)';
}

/// Represents a function/tool execution result sent back to the LLM
class FunctionResponse {
  final String id;
  final String name;
  final Map<String, dynamic> result;

  const FunctionResponse({
    required this.id,
    required this.name,
    required this.result,
  });
}

/// Tool declaration for Gemini function calling
class ToolDeclaration {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  const ToolDeclaration({
    required this.name,
    required this.description,
    required this.parameters,
  });
}

/// Generation configuration
class GenerationConfig {
  final double temperature;
  final String? speechConfig;

  const GenerationConfig({
    this.temperature = 0.7,
    this.speechConfig,
  });
}

/// Abstract interface for any LLM provider.
/// Phase 1 implements GeminiLiveProvider.
/// Future: OpenAILiveProvider, ClaudeProvider, LocalLLMProvider.
abstract class LlmProvider {
  /// Connect to the LLM service
  Future<void> connect({
    required String systemInstruction,
    required List<ToolDeclaration> tools,
    GenerationConfig? config,
  });

  /// Send audio chunk for real-time processing
  void sendAudio(List<int> pcmBytes);

  /// Send text message
  void sendText(String text);

  /// Send tool execution result back to LLM
  Future<void> sendToolResponse(List<FunctionResponse> responses);

  /// Stream of text responses from the LLM
  Stream<String> get textStream;

  /// Stream of audio (TTS) responses from the LLM
  Stream<List<int>> get audioStream;

  /// Stream of function call requests from the LLM
  Stream<FunctionCall> get toolCallStream;

  /// Stream of connection state changes
  Stream<ConnectionState> get connectionStateStream;

  /// Stream of interruption events (barge-in).
  /// Emits when the user interrupts the model mid-response,
  /// signalling that any in-progress audio playback should be
  /// immediately stopped and buffers cleared.
  Stream<void> get interruptionStream;

  /// Disconnect and clean up
  Future<void> disconnect();
}
