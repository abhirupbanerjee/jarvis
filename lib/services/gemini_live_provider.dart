// lib/services/gemini_live_provider.dart — Gemini Live Provider Implementation
//
// Implements the LlmProvider interface using googleai_dart's Live API WebSocket.
// Handles connection lifecycle, reconnection with exponential backoff,
// audio/text streaming, and tool/function calling.
//
// Auth modes:
// - Ephemeral tokens (production): Fetches short-lived token from backend,
//   passes it via accessToken on connect(). The real API key never touches
//   the client device.
// - Direct API key (development): Uses the key directly from .env.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:googleai_dart/googleai_dart.dart' as gai;
import 'package:logging/logging.dart';

import '../config/llm_config.dart';
import '../providers/llm_provider.dart';

final _log = Logger('GeminiLiveProvider');

class GeminiLiveProvider implements LlmProvider {
  final LlmConfig _llmConfig;
  final gai.GoogleAIClient _client;

  // Reconnection state
  static const _maxRetries = 5;
  static const _baseDelay = Duration(seconds: 1);
  static const _maxDelay = Duration(seconds: 30);
  int _retryCount = 0;
  int _audioFramesSent = 0;

  // Cached session config for reconnection
  String? _cachedSystemInstruction;
  List<ToolDeclaration>? _cachedTools;
  GenerationConfig? _cachedConfig;

  // Live session
  gai.LiveClient? _liveClient;
  gai.LiveSession? _session;
  StreamSubscription<gai.BidiGenerateContentServerMessage>? _messageSubscription;

  // Stream controllers
  final _textStreamController = StreamController<String>.broadcast();
  final _audioStreamController = StreamController<List<int>>.broadcast();
  final _toolCallStreamController = StreamController<FunctionCall>.broadcast();
  final _connectionStateController =
      StreamController<ConnectionState>.broadcast();
  final _interruptionStreamController = StreamController<void>.broadcast();
  final _turnCompleteStreamController = StreamController<void>.broadcast();

  GeminiLiveProvider({
    required LlmConfig llmConfig,
  })  : _llmConfig = llmConfig,
        _client = gai.GoogleAIClient(
          config: gai.GoogleAIConfig.googleAI(
            authProvider: llmConfig.useEphemeralTokens
                ? gai.NoAuthProvider()
                : gai.ApiKeyProvider(llmConfig.apiKey),
          ),
        );

  // ── Public Streams ──

  @override
  Stream<String> get textStream => _textStreamController.stream;

  @override
  Stream<List<int>> get audioStream => _audioStreamController.stream;

  @override
  Stream<FunctionCall> get toolCallStream => _toolCallStreamController.stream;

  @override
  Stream<ConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  @override
  Stream<void> get interruptionStream =>
      _interruptionStreamController.stream;

  @override
  Stream<void> get turnCompleteStream =>
      _turnCompleteStreamController.stream;

  // ── Connection Management ──

  @override
  Future<void> connect({
    required String systemInstruction,
    required List<ToolDeclaration> tools,
    GenerationConfig? config,
  }) async {
    _log.info('connect() called — model=${_llmConfig.modelId}, '
        'authMode=${_llmConfig.useEphemeralTokens ? "ephemeral" : "apiKey"}');

    // Validate configuration
    if (!_llmConfig.isValid) {
      _emitConnectionState(ConnectionState.error);
      _log.severe('Invalid or missing configuration');
      return;
    }

    // Cache for reconnection
    _cachedSystemInstruction = systemInstruction;
    _cachedTools = tools;
    _cachedConfig = config;

    _emitConnectionState(ConnectionState.connecting);
    _audioFramesSent = 0;

    try {
      // Clean up previous session
      await _cleanupPreviousSession();

      // Fetch ephemeral token if using token-based auth
      String? accessToken;
      if (_llmConfig.useEphemeralTokens) {
        accessToken = await _fetchEphemeralToken();
        if (accessToken == null) {
          _emitConnectionState(ConnectionState.error);
          _log.severe('Failed to fetch ephemeral token');
          return;
        }
      }

      // Create live client
      _liveClient = _client.createLiveClient();

      // Build Gemini-native tool declarations
      final geminiTools = tools.map((t) => gai.Tool(
            functionDeclarations: [
              gai.FunctionDeclaration(
                name: t.name,
                description: t.description,
                parameters: _toGeminiSchema(t.parameters),
              ),
            ],
          )).toList();

      // Build live config with auto VAD for audio turn detection
      final liveConfig = gai.LiveConfig(
        systemInstruction: gai.Content(
          parts: [gai.TextPart(systemInstruction)],
          role: 'user',
        ),
        tools: geminiTools.isNotEmpty ? geminiTools : null,
        generationConfig: gai.LiveGenerationConfig.audioOnly(
          speechConfig: gai.SpeechConfig.withVoice(_llmConfig.voice),
          temperature: config?.temperature ?? _llmConfig.temperature,
        ),
        realtimeInputConfig: gai.RealtimeInputConfig.withVAD(),
      );

      _session = await _liveClient!.connect(
        model: _llmConfig.modelId,
        liveConfig: liveConfig,
        accessToken: accessToken,
      );

      _emitConnectionState(ConnectionState.connected);
      _retryCount = 0; // Reset on successful connect

      // Wire up response handling
      _messageSubscription = _session!.messages.listen(
        _handleServerMessage,
        onError: _handleStreamError,
        onDone: _handleStreamDone,
      );

      _log.info('Connected to Gemini Live: model=${_llmConfig.modelId}');
    } catch (e, stack) {
      _log.severe('Failed to connect to Gemini Live', e, stack);
      _emitConnectionState(ConnectionState.error);

      // Attempt reconnection
      if (_retryCount < _maxRetries) {
        await _handleReconnect();
      }
    }
  }

  // ── Message Handling ──

  void _handleServerMessage(gai.BidiGenerateContentServerMessage message) {
    switch (message) {
      // Tool call request from the model
      case gai.BidiGenerateContentToolCall(:final functionCalls):
        for (final call in functionCalls) {
          _toolCallStreamController.add(FunctionCall(
            id: call.id ?? '',
            name: call.name,
            args: _safeArgs(call.args),
          ));
          _log.info('Function call received: ${call.name}');
        }

      // Tool call cancellation (user interrupted before tools executed)
      case gai.BidiGenerateContentToolCallCancellation(:final ids):
        _log.info('Tool calls cancelled due to interruption: $ids');
        _interruptionStreamController.add(null);

      // Model content response
      case gai.BidiGenerateContentServerContent(
            :final modelTurn,
            :final interrupted,
            :final turnComplete,
          ):
        // Handle barge-in: user interrupted the model mid-response
        if (interrupted == true) {
          _log.info('Model interrupted by user speech (barge-in)');
          _interruptionStreamController.add(null);
        }
        // Signal turn completion so audio/text can be committed
        if (turnComplete == true) {
          _log.info('Model turn complete — signalling commit');
          _turnCompleteStreamController.add(null);
        }
        _log.info('ServerContent: modelTurn=${modelTurn != null}, parts=${modelTurn?.parts.length ?? 0}, interrupted=$interrupted, turnComplete=$turnComplete');
        if (modelTurn != null) {
          for (final part in modelTurn.parts) {
            _log.info('  Part: ${part.runtimeType}');
            if (part is gai.TextPart && part.text.isNotEmpty) {
              // Skip model thinking/reasoning — only stream final response text
              if (part.thought == true) {
                _log.fine('Skipping thought: "${part.text.length > 50 ? '${part.text.substring(0, 50)}...' : part.text}"');
                continue;
              }
              _log.info('Gemini text: "${part.text.length > 80 ? '${part.text.substring(0, 80)}...' : part.text}"');
              _textStreamController.add(part.text);
            }
            if (part is gai.InlineDataPart) {
              final decoded = base64Decode(part.inlineData.data);
              _log.info('Gemini audio: ${decoded.length} PCM bytes');
              _audioStreamController.add(decoded);
            }
          }
        }

      // Setup complete
      case gai.BidiGenerateContentSetupComplete():
        _log.info('Setup complete: ${message.sessionId ?? "no ID"}');

      // Resumption token
      case gai.SessionResumptionUpdate():
        _log.info('Resumption token updated');

      // Server drain
      case gai.GoAway():
        _log.info('Server drain, reconnecting');
        _handleStreamDone();

      // Unknown
      default:
        _log.info('Unknown message: ${message.runtimeType} — $message');
    }
  }

  void _handleStreamError(Object error) {
    _log.severe('Stream error', error);
    _emitConnectionState(ConnectionState.error);
  }

  void _handleStreamDone() {
    _log.info('Stream closed');
    _emitConnectionState(ConnectionState.disconnected);
    if (_retryCount < _maxRetries) {
      _handleReconnect();
    }
  }

  // ── Reconnection ──

  Future<void> _handleReconnect() async {
    if (_cachedSystemInstruction == null || _cachedTools == null) return;
    final delay = _calculateBackoff(_retryCount);
    _retryCount++;
    _emitConnectionState(ConnectionState.connecting);
    _log.info('Reconnecting in ${delay.inSeconds}s (attempt $_retryCount/$_maxRetries)');
    await Future.delayed(delay);
    await connect(
      systemInstruction: _cachedSystemInstruction!,
      tools: _cachedTools!,
      config: _cachedConfig,
    );
  }

  Duration _calculateBackoff(int retry) {
    final ms = _baseDelay.inMilliseconds * pow(2, retry);
    return Duration(milliseconds: min(ms.toInt(), _maxDelay.inMilliseconds));
  }

  // ── Sending ──

  @override
  void sendAudio(List<int> pcmBytes) {
    _audioFramesSent++;
    if (_audioFramesSent % 50 == 1) {
      _log.info('sendAudio: #$_audioFramesSent, ${pcmBytes.length}B, session=${_session != null}');
    }
    _session?.sendAudio(pcmBytes);
  }

  @override
  void sendText(String text) {
    if (_session == null) {
      _log.warning('sendText called but session is null — text not sent');
      return;
    }
    try {
      _session!.sendText(text);
    } catch (e, stack) {
      _log.severe('Failed to send text via WebSocket', e, stack);
    }
  }

  @override
  Future<void> sendToolResponse(List<FunctionResponse> responses) async {
    if (_session == null) return;
    _session!.sendToolResponse(responses.map((r) => gai.FunctionResponse(
      id: r.id,
      name: r.name,
      response: r.result,
    )).toList());
  }

  // ── Lifecycle ──

  Future<void> _cleanupPreviousSession() async {
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    await _session?.close();
    _session = null;
  }

  @override
  Future<void> disconnect() async {
    _retryCount = _maxRetries;
    await _cleanupPreviousSession();
    await _liveClient?.close();
    _liveClient = null;
    _emitConnectionState(ConnectionState.disconnected);
    _log.info('Disconnected');
  }

  Future<void> dispose() async {
    await disconnect();
    await _textStreamController.close();
    await _audioStreamController.close();
    await _toolCallStreamController.close();
    await _connectionStateController.close();
    await _interruptionStreamController.close();
    await _turnCompleteStreamController.close();
    _client.close();
  }

  // ── Ephemeral Token ──

  /// Fetch a short-lived ephemeral token from the backend.
  /// Returns the token string, or null on failure.
  Future<String?> _fetchEphemeralToken() async {
    try {
      final endpoint = _llmConfig.tokenEndpoint;
      final secret = _llmConfig.tokenAuthSecret;

      _log.info('Fetching ephemeral token from $endpoint');

      final client = HttpClient();
      try {
        final request = await client.postUrl(Uri.parse(endpoint));
        request.headers.set('Authorization', 'Bearer $secret');
        request.headers.set('Content-Type', 'application/json');

        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();

        if (response.statusCode != 200) {
          _log.severe('Token endpoint returned ${response.statusCode}: $body');
          return null;
        }

        final json = jsonDecode(body) as Map<String, dynamic>;
        final token = json['token'] as String?;

        if (token == null || token.isEmpty) {
          _log.severe('Token endpoint returned empty token');
          return null;
        }

        _log.info('Ephemeral token obtained (${token.length} chars)');
        return token;
      } finally {
        client.close();
      }
    } catch (e) {
      _log.severe('Failed to fetch ephemeral token: $e');
      return null;
    }
  }

  // ── Helpers ──

  void _emitConnectionState(ConnectionState state) {
    _connectionStateController.add(state);
  }

  Map<String, dynamic> _safeArgs(dynamic args) {
    if (args is Map<String, dynamic>) return args;
    if (args is Map) return args.map((k, v) => MapEntry(k.toString(), v));
    return {};
  }

  gai.Schema? _toGeminiSchema(Map<String, dynamic> params) {
    if (params.isEmpty) return null;
    final typeStr = params['type'] as String?;
    final schemaType = typeStr != null ? _mapSchemaType(typeStr) : null;

    Map<String, dynamic>? safeProps(dynamic v) {
      if (v is Map) return Map<String, dynamic>.from(v);
      return null;
    }

    final properties = safeProps(params['properties']);
    return gai.Schema(
      type: schemaType,
      description: params['description'] as String?,
      properties: properties?.map(
        (key, value) => MapEntry(key, _toGeminiSchema(safeProps(value)!)!),
      ),
      required: (params['required'] as List?)?.cast<String>(),
      enumValues: (params['enum'] as List?)?.map((e) => e.toString()).toList(),
    );
  }

  gai.SchemaType _mapSchemaType(String type) {
    return switch (type) {
      'string' => gai.SchemaType.string,
      'number' => gai.SchemaType.number,
      'integer' => gai.SchemaType.integer,
      'boolean' => gai.SchemaType.boolean,
      'array' => gai.SchemaType.array,
      'object' => gai.SchemaType.object,
      _ => gai.SchemaType.unspecified,
    };
  }
}
