// lib/providers/chat_provider.dart — Chat Orchestrator

import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:logging/logging.dart';

import '../data/database.dart';
import '../providers/database_provider.dart';
import '../providers/llm_provider.dart';
import '../providers/llm_provider_provider.dart';
import '../providers/memory_provider.dart';
import '../services/audio_pipeline.dart';
import '../services/error_handler.dart';
import '../tools/tool_registry.dart';

final _log = Logger('ChatProvider');

/// Represents a single chat message
class ChatMessage {
  final String text;
  final bool isUser;
  final bool isSystem;
  final DateTime timestamp;

  const ChatMessage({
    required this.text,
    this.isUser = false,
    this.isSystem = false,
    required this.timestamp,
  });
}

/// States for the chat session
enum ChatSessionState {
  idle,
  connecting,
  listening,
  thinking,
  speaking,
  error,
}

/// Immutable state object for ChatNotifier.
/// All UI-visible fields live here so that assigning a new instance
/// triggers proper Riverpod widget rebuilds.
class ChatSessionData {
  final ChatSessionState sessionState;
  final List<ChatMessage> messages;
  final String currentResponse;
  final String toolStatus;
  final String lastError;

  const ChatSessionData({
    this.sessionState = ChatSessionState.idle,
    this.messages = const [],
    this.currentResponse = '',
    this.toolStatus = '',
    this.lastError = '',
  });

  static const initial = ChatSessionData();

  ChatSessionData copyWith({
    ChatSessionState? sessionState,
    List<ChatMessage>? messages,
    String? currentResponse,
    String? toolStatus,
    String? lastError,
  }) {
    return ChatSessionData(
      sessionState: sessionState ?? this.sessionState,
      messages: messages ?? this.messages,
      currentResponse: currentResponse ?? this.currentResponse,
      toolStatus: toolStatus ?? this.toolStatus,
      lastError: lastError ?? this.lastError,
    );
  }
}

/// Manages the full chat session lifecycle
class ChatNotifier extends StateNotifier<ChatSessionData> {
  final Ref _ref;
  final ErrorHandler _errorHandler = ErrorHandler();

  AudioPipeline? _audioPipeline;
  StreamSubscription? _textSub;
  StreamSubscription? _toolSub;
  StreamSubscription? _connectionSub;
  StreamSubscription? _audioSub;
  StreamSubscription? _interruptSub;
  StreamSubscription? _turnCompleteSub;

  // Audio playback
  final AudioPlayer _audioPlayer = AudioPlayer();
  final List<int> _audioBuffer = [];

  // ─────────────────────────────────────────────
  // Gemini Live API sample rate for textAndAudio mode
  // ─────────────────────────────────────────────
  static const _geminiSampleRate = 24000;
  static const _geminiBitsPerSample = 16;
  static const _geminiChannels = 1;

  ChatNotifier(this._ref) : super(ChatSessionData.initial);

  // ── Public getters (delegate to immutable state) ──

  List<ChatMessage> get chatMessages => state.messages;
  String get currentResponse => state.currentResponse;
  String get toolStatus => state.toolStatus;
  String get lastError => state.lastError;

  /// Start a new chat session — connect to Gemini Live and begin listening
  Future<void> startSession() async {
    if (state.sessionState != ChatSessionState.idle) return;

    state = state.copyWith(sessionState: ChatSessionState.connecting);

    try {
      final llmProvider = _ref.read(llmProviderProvider);

      // Build system instruction with injected memories
      final db = _ref.read(databaseProvider);
      final systemInstruction = await buildSystemInstruction(db);

      // Wire up connection state stream BEFORE connecting
      // (must subscribe early to catch connection errors)
      _connectionSub = llmProvider.connectionStateStream.listen(
        (connState) {
          if (connState == ConnectionState.error) {
            // Only show error if session was already active — transient
            // reconnects during initial connect() should not flash "Error".
            final isActive = state.sessionState == ChatSessionState.listening ||
                state.sessionState == ChatSessionState.thinking ||
                state.sessionState == ChatSessionState.speaking;
            if (isActive) {
              state = state.copyWith(
                sessionState: ChatSessionState.error,
                lastError: 'Connection lost. Tap mic to retry.',
              );
            }
          }
        },
      );

      // Wire up text stream
      _textSub = llmProvider.textStream.listen(
        (text) {
          _log.fine('Text received: "${text.length > 50 ? '${text.substring(0, 50)}...' : text}"');
          state = state.copyWith(
            currentResponse: state.currentResponse + text,
          );
        },
        onError: _handleError,
      );

      // Wire up tool call stream
      _toolSub = llmProvider.toolCallStream.listen(
        (call) {
          state = state.copyWith(
            toolStatus: 'Working: ${call.name}...',
          );
          _executeTool(call);
        },
        onError: _handleError,
      );

      // Wire up audio stream — buffer PCM data for TTS playback
      _audioBuffer.clear();
      _audioSub = llmProvider.audioStream.listen(
        (pcmChunk) {
          _log.fine('Audio chunk: ${pcmChunk.length} bytes (total buffered: ${_audioBuffer.length + pcmChunk.length})');
          _audioBuffer.addAll(pcmChunk);
        },
        onError: (e) {
          _log.warning('Audio stream error: $e');
        },
      );

      // Wire up interruption stream — handle barge-in (user interrupts AI)
      _interruptSub = llmProvider.interruptionStream.listen((_) {
        _log.info('Barge-in detected: stopping playback and clearing buffers');
        _audioPlayer.stop();
        _audioBuffer.clear();
        // Discard partial response since it was interrupted
        if (state.currentResponse.isNotEmpty) {
          state = state.copyWith(currentResponse: '');
        }
      });

      // Wire up turn-complete stream — auto-commit when model finishes generating
      _turnCompleteSub = llmProvider.turnCompleteStream.listen((_) {
        _log.info('Turn complete — committing response');
        final audioTriggered = _commitResponse();
        if (!audioTriggered) {
          state = state.copyWith(sessionState: ChatSessionState.listening);
        }
        // If audio was triggered, _playBufferedAudio() handles state transitions
      });

      // Connect to Gemini Live with all tools (AFTER setting up listeners)
      final toolDeclarations =
          toolRegistry.map((t) => t.toDeclaration()).toList();

      await llmProvider.connect(
        systemInstruction: systemInstruction,
        tools: toolDeclarations,
      );

      // Load chat history from database
      final db = _ref.read(databaseProvider);
      final history = await db.loadRecentMessages();
      if (history.isNotEmpty) {
        final loadedMessages = history.map((m) => ChatMessage(
          text: m.text,
          isUser: m.isUser,
          isSystem: m.isSystem,
          timestamp: m.timestamp,
        )).toList();
        state = state.copyWith(messages: loadedMessages);
        _log.info('Loaded ${loadedMessages.length} messages from history');
      }

      // Setup audio pipeline
      _audioPipeline = AudioPipeline(llmProvider: llmProvider);

      await _audioPipeline!.startListening();
      state = state.copyWith(sessionState: ChatSessionState.listening);

      _addSystemMessage('Listening...');
      _pushWidgetState('listening');
      _log.info('Chat session started');
    } catch (e, stack) {
      _log.severe('Failed to start session', e, stack);
      state = state.copyWith(
        sessionState: ChatSessionState.error,
        lastError: _errorHandler.categorize(e, stack).userFacingMessage,
      );
    }
  }

  /// Stop listening but keep session alive.
  /// Commits any pending response before resetting.
  Future<void> stopListening() async {
    // Allow stopping from listening, thinking, or speaking states
    if (state.sessionState != ChatSessionState.listening &&
        state.sessionState != ChatSessionState.thinking &&
        state.sessionState != ChatSessionState.speaking) {
      return;
    }
    _commitResponse();
    await _audioPipeline?.stopListening();
    // Remove stale "Listening..." system message when session ends
    final cleanedMessages = state.messages
        .where((m) => !(m.isSystem && m.text == 'Listening...'))
        .toList();
    state = state.copyWith(
      sessionState: ChatSessionState.idle,
      toolStatus: '',
      messages: cleanedMessages,
    );
    _pushWidgetState('idle');
  }

  /// End the chat session completely
  Future<void> endSession() async {
    await _audioPipeline?.dispose();
    _audioPipeline = null;
    await _textSub?.cancel();
    await _toolSub?.cancel();
    await _connectionSub?.cancel();
    await _audioSub?.cancel();
    await _interruptSub?.cancel();
    await _turnCompleteSub?.cancel();

    final llmProvider = _ref.read(llmProviderProvider);
    await llmProvider.disconnect();

    // Remove stale "Listening..." system message
    final cleanedMessages = state.messages
        .where((m) => !(m.isSystem && m.text == 'Listening...'))
        .toList();
    state = state.copyWith(
      sessionState: ChatSessionState.idle,
      toolStatus: '',
      messages: cleanedMessages,
    );
    _pushWidgetState('idle');
    _log.info('Chat session ended');
  }

  /// Send a text prompt and add it to chat history as a user message.
  /// The model's response streams in via the existing _textSub listener
  /// and is committed on turnComplete via _commitResponse().
  Future<void> sendTextPrompt(String text) async {
    // Add user message to chat history
    final message = ChatMessage(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(
      messages: [
        ...state.messages,
        message,
      ],
      sessionState: ChatSessionState.thinking,
      currentResponse: '',
    );

    // Persist user message (fire-and-forget)
    _persistMessage(message);

    // Send to LLM
    final llmProvider = _ref.read(llmProviderProvider);
    llmProvider.sendText(text);
  }

  /// Toggle listening — tap mic to start/stop
  Future<void> toggleListening() async {
    if (state.sessionState == ChatSessionState.idle ||
        state.sessionState == ChatSessionState.error) {
      // Commit current response as a message before starting new session
      _commitResponse();
      await startSession();
    } else if (state.sessionState == ChatSessionState.listening ||
               state.sessionState == ChatSessionState.thinking ||
               state.sessionState == ChatSessionState.speaking) {
      _commitResponse();
      await stopListening();
    }
    // connecting state: do nothing (let connection establish)
  }

  /// Execute a tool call from the LLM
  Future<void> _executeTool(FunctionCall call) async {
    final tool = toolRegistry.cast<ToolDefinition?>().firstWhere(
          (t) => t?.name == call.name,
          orElse: () => null,
        );

    if (tool == null) {
      _log.warning('Unknown tool: ${call.name}');
      final llmProvider = _ref.read(llmProviderProvider);
      await llmProvider.sendToolResponse([
        FunctionResponse(
          id: call.id,
          name: call.name,
          result: {'error': 'Unknown tool: ${call.name}'},
        ),
      ]);
      state = state.copyWith(toolStatus: '');
      return;
    }

    try {
      final result = await tool.executor(call.args);

      final llmProvider = _ref.read(llmProviderProvider);
      await llmProvider.sendToolResponse([
        FunctionResponse(
          id: call.id,
          name: call.name,
          result: result,
        ),
      ]);
    } catch (e, stack) {
      _log.severe('Tool execution failed: ${call.name}', e, stack);

      final llmProvider = _ref.read(llmProviderProvider);
      await llmProvider.sendToolResponse([
        FunctionResponse(
          id: call.id,
          name: call.name,
          result: {'error': e.toString()},
        ),
      ]);
    }

    state = state.copyWith(toolStatus: '');
  }

  void _handleError(Object error) {
    final jarvisError =
        _errorHandler.categorize(error, StackTrace.current);
    state = state.copyWith(lastError: jarvisError.userFacingMessage);
    _addSystemMessage(jarvisError.userFacingMessage);
  }

  void _addSystemMessage(String text) {
    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage(
          text: text,
          isSystem: true,
          timestamp: DateTime.now(),
        ),
      ],
    );
  }

  /// Commits the current streaming response to message history.
  /// Returns true if audio playback was triggered.
  bool _commitResponse() {
    final hasText = state.currentResponse.isNotEmpty;
    final hasAudio = _audioBuffer.isNotEmpty;

    _log.info('_commitResponse: hasText=$hasText hasAudio=$hasAudio '
        'textLen=${state.currentResponse.length} audioLen=${_audioBuffer.length}');

    if (hasText) {
      final message = ChatMessage(
        text: state.currentResponse.trim(),
        isUser: false,
        timestamp: DateTime.now(),
      );
      state = state.copyWith(
        messages: [
          ...state.messages,
          message,
        ],
        currentResponse: '',
      );

      // Persist to database (fire-and-forget)
      _persistMessage(message);
    }

    // Play audio regardless of whether text arrived — Gemini may respond
    // with audio-only (textAndAudio mode without transcription).
    if (hasAudio) {
      _playBufferedAudio();
      return true;
    }
    return false;
  }

  // ── Audio Playback ──

  /// Play buffered PCM audio from Gemini TTS via audioplayers.
  /// Converts raw PCM to a WAV container in memory before playback.
  Future<void> _playBufferedAudio() async {
    if (_audioBuffer.isEmpty) return;

    _log.info('Playing TTS audio: ${_audioBuffer.length} raw PCM bytes');

    // Signal that JARVIS is speaking
    state = state.copyWith(sessionState: ChatSessionState.speaking);
    _pushWidgetState('speaking');

    try {
      final wavBytes = _pcmToWav(
        pcmData: Uint8List.fromList(_audioBuffer),
        sampleRate: _geminiSampleRate,
        bitsPerSample: _geminiBitsPerSample,
        channels: _geminiChannels,
      );

      await _audioPlayer.stop(); // Stop any previous playback
      await _audioPlayer.play(BytesSource(wavBytes));
      _log.info('Playing TTS audio (${_audioBuffer.length} PCM bytes → ${wavBytes.length} WAV bytes)');
    } catch (e) {
      _log.warning('Audio playback failed: $e');
    } finally {
      _audioBuffer.clear();
      // Return to listening state after playback completes,
      // unless interrupted (barge-in may have changed the state)
      if (state.sessionState == ChatSessionState.speaking) {
        state = state.copyWith(sessionState: ChatSessionState.listening);
        _pushWidgetState('listening');
      }
    }
  }

  /// Encode raw 16-bit PCM samples into a WAV container.
  /// Returns the complete .wav file as bytes (44-byte header + data).
  static Uint8List _pcmToWav({
    required Uint8List pcmData,
    required int sampleRate,
    required int bitsPerSample,
    required int channels,
  }) {
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = pcmData.length;
    final fileSize = 36 + dataSize;

    final header = ByteData(44);
    int offset = 0;

    // RIFF header
    header.setUint8(offset, 0x52); // 'R'
    header.setUint8(offset + 1, 0x49); // 'I'
    header.setUint8(offset + 2, 0x46); // 'F'
    header.setUint8(offset + 3, 0x46); // 'F'
    header.setUint32(offset + 4, fileSize, Endian.little);
    offset += 8;

    // WAVEfmt 
    header.setUint8(offset, 0x57); // 'W'
    header.setUint8(offset + 1, 0x41); // 'A'
    header.setUint8(offset + 2, 0x56); // 'V'
    header.setUint8(offset + 3, 0x45); // 'E'
    header.setUint8(offset + 4, 0x66); // 'f'
    header.setUint8(offset + 5, 0x6D); // 'm'
    header.setUint8(offset + 6, 0x74); // 't'
    header.setUint8(offset + 7, 0x20); // ' '
    header.setUint32(offset + 8, 16, Endian.little); // Subchunk1 size (PCM = 16)
    header.setUint16(offset + 12, 1, Endian.little); // Audio format (1 = PCM)
    header.setUint16(offset + 14, channels, Endian.little);
    header.setUint32(offset + 16, sampleRate, Endian.little);
    header.setUint32(offset + 20, byteRate, Endian.little);
    header.setUint16(offset + 24, blockAlign, Endian.little);
    header.setUint16(offset + 26, bitsPerSample, Endian.little);
    offset += 28;

    // data subchunk
    header.setUint8(offset, 0x64); // 'd'
    header.setUint8(offset + 1, 0x61); // 'a'
    header.setUint8(offset + 2, 0x74); // 't'
    header.setUint8(offset + 3, 0x61); // 'a'
    header.setUint32(offset + 4, dataSize, Endian.little);

    return Uint8List.fromList([
      ...header.buffer.asUint8List(),
      ...pcmData,
    ]);
  }

  /// Persist a chat message to the database (fire-and-forget).
  void _persistMessage(ChatMessage message) {
    try {
      final db = _ref.read(databaseProvider);
      db.saveMessage(
        text: message.text,
        isUser: message.isUser,
        isSystem: message.isSystem,
        timestamp: message.timestamp,
      );
    } catch (e) {
      _log.warning('Failed to persist message: $e');
    }
  }

  /// Push session state to the home screen widget.
  void _pushWidgetState(String status) {
    try {
      HomeWidget.saveWidgetData('widget_status', status);
      HomeWidget.updateWidget(androidName: 'JarvisWidgetProvider');
    } catch (_) {
      // Widget update is best-effort; don't crash if it fails
    }
  }

  @override
  void dispose() {
    endSession();
    _audioPlayer.dispose();
    super.dispose();
  }
}

/// Riverpod provider for chat state
final chatProvider =
    StateNotifierProvider<ChatNotifier, ChatSessionData>((ref) {
  return ChatNotifier(ref);
});
