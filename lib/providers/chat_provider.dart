// lib/providers/chat_provider.dart — Chat Orchestrator

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:home_widget/home_widget.dart';
import 'package:logging/logging.dart';

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

  // Low-latency streaming audio playback via SoLoud
  AudioSource? _soloudAudioSource;
  SoundHandle? _soloudHandle;
  StreamSubscription<void>? _audioStreamFinishedSub;
  bool _isAudioStreamActive = false;
  bool _isCommitting = false;
  DateTime? _firstAudioChunkTime;
  int _audioBytesFed = 0;

  // Gemini native audio model outputs 24 kHz PCM16 mono.
  static const _geminiSampleRate = 24000;

  // (We no longer resample to 48 kHz; SoLoud streams the native 24 kHz
  // PCM directly. Android's AudioFlinger resamples 24 kHz → 48 kHz using
  // a simple 1:2 ratio, which is efficient and low-latency.)

  ChatNotifier(this._ref) : super(ChatSessionData.initial);

  // ── Public getters (delegate to immutable state) ──

  List<ChatMessage> get chatMessages => state.messages;
  String get currentResponse => state.currentResponse;
  String get toolStatus => state.toolStatus;
  String get lastError => state.lastError;

  /// Start a new chat session — connect to Gemini Live and begin listening
  Future<void> startSession() async {
    if (state.sessionState != ChatSessionState.idle) return;

    // Clean up any stale subscriptions from a previous session before
    // starting a fresh one. This prevents duplicate audio/text streams
    // when the user taps the mic after a completed turn.
    await _cancelSubscriptions();

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
            // Handle both initial connection failure and mid-session drops
            final isActive = state.sessionState == ChatSessionState.listening ||
                state.sessionState == ChatSessionState.thinking ||
                state.sessionState == ChatSessionState.speaking;
            final isConnecting =
                state.sessionState == ChatSessionState.connecting;
            if (isActive) {
              state = state.copyWith(
                sessionState: ChatSessionState.error,
                lastError: 'Connection lost. Check your network and tap mic to retry.',
              );
            } else if (isConnecting) {
              // Initial connect() failed — set error so startSession()
              // can detect it and stop further setup.
              state = state.copyWith(
                sessionState: ChatSessionState.error,
                lastError: 'Connection failed. Check your API key and network.',
              );
            }
          }
        },
      );

      // Wire up text stream
      _textSub = llmProvider.textStream.listen(
        (text) {
          _log.fine('Text received (${text.length} chars)');
          state = state.copyWith(
            currentResponse: state.currentResponse + text,
          );
        },
        onError: _handleError,
      );

      // Wire up tool call stream
      _toolSub = llmProvider.toolCallStream.listen(
        (call) {
          _log.info('_toolSub FIRED: ${call.name}, args=${call.args}');
          state = state.copyWith(
            toolStatus: 'Working: ${call.name}...',
          );
          _executeTool(call);
        },
        onError: (e, st) {
          _log.severe('_toolSub error', e, st);
          _handleError(e);
        },
      );

      // Wire up audio stream — feed PCM chunks directly to SoLoud for
      // low-latency streaming playback. Audio starts as soon as the first
      // chunk arrives, not at turnComplete.
      _audioBytesFed = 0;
      _firstAudioChunkTime = null;
      _audioSub = llmProvider.audioStream.listen(
        (pcmChunk) {
          _feedAudioChunk(Uint8List.fromList(pcmChunk));
        },
        onError: (e) {
          _log.warning('Audio stream error: $e');
        },
      );

      // Wire up interruption stream — handle barge-in (user interrupts AI)
      _interruptSub = llmProvider.interruptionStream.listen((_) {
        _log.info('Barge-in detected: stopping playback and clearing buffers');
        _abortPlaybackAndClearBuffers();
        // Discard partial response since it was interrupted
        if (state.currentResponse.isNotEmpty) {
          state = state.copyWith(currentResponse: '');
        }
      });

      // Wire up turn-complete stream — auto-commit when model finishes generating.
      // With SoLoud streaming, audio is already playing; turnComplete just tells
      // the stream no more data is coming and commits any text.
      _turnCompleteSub = llmProvider.turnCompleteStream.listen((_) async {
        _log.info('Turn complete — committing response');

        // If the model is responding and the last chat message isn't from the
        // user, the input must have been voice. Insert a placeholder so the
        // chat history shows that the user said something.
        if (state.messages.isEmpty || !state.messages.last.isUser) {
          final placeholder = ChatMessage(
            text: '🎤 Voice input',
            isUser: true,
            timestamp: DateTime.now(),
          );
          state = state.copyWith(
            messages: [...state.messages, placeholder],
          );
          _persistMessage(placeholder);
        }

        final audioStarted = _isAudioStreamActive;
        await _commitResponse();

        // Tell SoLoud to finish playing whatever is buffered.
        if (_soloudAudioSource != null) {
          final elapsed = _firstAudioChunkTime != null
              ? DateTime.now().difference(_firstAudioChunkTime!).inMilliseconds
              : 0;
          _log.info('Turn complete — marking SoLoud stream as ended '
              '(audio streamed for ${elapsed}ms, $_audioBytesFed bytes fed)');
          SoLoud.instance.setDataIsEnded(_soloudAudioSource!);
        }

        if (!audioStarted) {
          // Text-only or no audio response: go idle now.
          state = state.copyWith(sessionState: ChatSessionState.idle);
          _pushWidgetState('idle');
        }
        // If audio was started, allInstancesFinished transitions to idle once
        // the buffered stream finishes playing.
      });

      // Connect to Gemini Live with all tools (AFTER setting up listeners)
      final toolDeclarations =
          toolRegistry.map((t) => t.toDeclaration()).toList();

      await llmProvider.connect(
        systemInstruction: systemInstruction,
        tools: toolDeclarations,
      );

      // If connect() failed (model rejected config, auth error, etc.),
      // the connection-state listener already set state to error — stop.
      if (state.sessionState == ChatSessionState.error) return;

      // Load chat history from database
      final history = await db.loadRecentMessages();
      if (history.isNotEmpty) {
        final loadedMessages = history.map((m) => ChatMessage(
          text: m.content,
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

      // Allow server-side VAD to stabilize before the user is told to speak.
      // The mic is already recording so the VAD can calibrate on ambient audio.
      await Future.delayed(const Duration(milliseconds: 500));

      state = state.copyWith(sessionState: ChatSessionState.listening);
      _pushWidgetState('listening');
      _log.info('VAD warm-up complete; chat session ready');
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
    // Stop any in-progress audio stream before committing to prevent a
    // race where the allInstancesFinished callback transitions us back to
    // speaking after we've gone idle.
    _stopAudioStream();
    await _commitResponse();
    await _audioPipeline?.stopListening();
    state = state.copyWith(
      sessionState: ChatSessionState.idle,
      toolStatus: '',
    );
    _pushWidgetState('idle');
  }

  /// Cancel all stream subscriptions without disconnecting the LLM provider.
  /// Used by startSession() to ensure a clean slate when re-entering from idle.
  Future<void> _cancelSubscriptions() async {
    await _textSub?.cancel();
    _textSub = null;
    await _toolSub?.cancel();
    _toolSub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    await _audioSub?.cancel();
    _audioSub = null;
    await _interruptSub?.cancel();
    _interruptSub = null;
    await _turnCompleteSub?.cancel();
    _turnCompleteSub = null;
    // Stop any lingering audio stream.
    _stopAudioStream();
  }

  /// End the chat session completely
  Future<void> endSession() async {
    // Stop any active audio stream and cancel subscriptions before tearing
    // down the session.
    await _cancelSubscriptions();
    await _audioPipeline?.dispose();
    _audioPipeline = null;

    final llmProvider = _ref.read(llmProviderProvider);
    await llmProvider.disconnect();

    state = state.copyWith(
      sessionState: ChatSessionState.idle,
      toolStatus: '',
    );
    _pushWidgetState('idle');
    _log.info('Chat session ended');
  }

  /// Clear all chat messages from state and database, ending any active
  /// session. Resets back to a clean idle state.
  Future<void> clearChat() async {
    // End any active session first (stops audio, disconnects, etc.)
    await endSession();

    // Clear persisted chat history from the database
    final db = _ref.read(databaseProvider);
    await db.clearHistory();

    // Reset to pristine initial state with no messages
    state = state.copyWith(messages: []);
    _log.info('Chat history cleared');
  }

  /// Send a text prompt and add it to chat history as a user message.
  /// The model's response streams in via the existing _textSub listener
  /// and is committed on turnComplete via _commitResponse().
  ///
  /// If the session is idle (not yet started), it auto-starts the session
  /// before sending. This allows text-only input without requiring a
  /// prior mic tap.
  Future<void> sendTextPrompt(String text) async {
    // Auto-start session if not already active.
    // NOTE: Do NOT set state to connecting here — startSession() checks
    // for idle state and will bail out early if state is already changed.
    if (state.sessionState == ChatSessionState.idle ||
        state.sessionState == ChatSessionState.error) {
      await startSession();
      // If session failed to start, don't proceed (error message
      // is already set by startSession's error handler)
      if (state.sessionState != ChatSessionState.listening) return;
    }

    // Guard against sending text while connection is still in progress
    if (state.sessionState == ChatSessionState.connecting) return;

    // If JARVIS is currently speaking, stop playback before sending
    // a new prompt so the speaking state doesn't overwrite thinking.
    if (state.sessionState == ChatSessionState.speaking) {
      _stopAudioStream();
    }

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
      await _commitResponse();
      await startSession();
    } else if (state.sessionState == ChatSessionState.listening ||
               state.sessionState == ChatSessionState.thinking ||
               state.sessionState == ChatSessionState.speaking) {
      await _commitResponse();
      await stopListening();
    }
    // connecting state: do nothing (let connection establish)
  }

  /// Explicitly stop the model's in-progress response and prepare for
  /// fresh user input. This is the UI-driven equivalent of barge-in.
  Future<void> stopResponding() async {
    _log.info('Stop button pressed: aborting model response');

    _abortPlaybackAndClearBuffers();

    // Discard any partial response text
    if (state.currentResponse.isNotEmpty) {
      state = state.copyWith(currentResponse: '');
    }

    // Reset commit guard in case a commit was interrupted
    _isCommitting = false;

    // Transition to listening so the user can immediately speak again.
    // The new audio will naturally interrupt the model on the server side.
    state = state.copyWith(sessionState: ChatSessionState.listening);
    _pushWidgetState('listening');
    await _audioPipeline?.startListening();
  }

  /// Shared helper: stop any active audio stream and clear playback state.
  /// Used by barge-in, the Stop button, and stopListening.
  void _abortPlaybackAndClearBuffers() {
    _stopAudioStream();
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
  /// Returns true if an audio stream was active during this response.
  Future<bool> _commitResponse() async {
    // Guard against duplicate commits — turnComplete, stopListening,
    // and toggleListening can all call this in quick succession.
    if (_isCommitting) {
      _log.fine('_commitResponse: already committing, skipping');
      return _isAudioStreamActive;
    }
    _isCommitting = true;

    final hasText = state.currentResponse.isNotEmpty;
    final audioStarted = _isAudioStreamActive;

    _log.fine('_commitResponse: hasText=$hasText audioStarted=$audioStarted '
        'textLen=${state.currentResponse.length} audioBytesFed=$_audioBytesFed');

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
    } else if (audioStarted) {
      // Audio-only mode (gemini-2.5-flash-native-audio): no TextPart
      // arrived, but audio was streamed. Insert a placeholder so the chat
      // history isn't empty and the user knows a response was given.
      final message = ChatMessage(
        text: '🎤 Voice response',
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
      _persistMessage(message);
    }

    _isCommitting = false;
    return audioStarted;
  }

  // ── Streaming Audio Playback (SoLoud) ──

  /// Feed a PCM chunk from Gemini Live into the SoLoud buffer stream.
  /// On the first chunk, a new stream is created, playback starts, and the
  /// state transitions to speaking. Subsequent chunks are appended directly.
  Future<void> _feedAudioChunk(Uint8List chunk) async {
    if (chunk.isEmpty) return;

    // Defensive guard: if the audio subscription has been canceled (e.g. the
    // session is being torn down or a new session is starting), drop the chunk
    // instead of feeding it into a stale or future stream.
    if (_audioSub == null) {
      _log.fine('Dropping audio chunk from stale subscription: ${chunk.length} bytes');
      return;
    }

    try {
      // Lazy-create the SoLoud buffer stream on the first chunk of a turn.
      if (_soloudAudioSource == null) {
        _firstAudioChunkTime = DateTime.now();
        _soloudAudioSource = SoLoud.instance.setBufferStream(
          bufferingType: BufferingType.released,
          sampleRate: _geminiSampleRate,
          channels: Channels.mono,
          format: BufferType.s16le,
        );
        // Disable auto-dispose so we can safely stop/dispose the source
        // ourselves without racing the native engine.
        _soloudAudioSource!.autoDispose = false;
        _isAudioStreamActive = true;
        _audioBytesFed = 0;

        _log.info('SoLoud stream started — first chunk: ${chunk.length} bytes');

        // Transition to speaking and pause mic capture to avoid echo.
        state = state.copyWith(sessionState: ChatSessionState.speaking);
        _pushWidgetState('speaking');
        _audioPipeline?.stopListening();

        _soloudHandle = SoLoud.instance.play(_soloudAudioSource!);
        _log.info('SoLoud playback started, handle=$_soloudHandle');

        // Listen for the stream to finish so we can transition to idle.
        _audioStreamFinishedSub = _soloudAudioSource!.allInstancesFinished.listen(
          (_) {
            _log.info('SoLoud stream finished');
            _finalizeSpeaking();
          },
          onError: (e) {
            _log.warning('SoLoud allInstancesFinished error: $e');
            _finalizeSpeaking();
          },
        );
      }

      SoLoud.instance.addAudioDataStream(_soloudAudioSource!, chunk);
      _audioBytesFed += chunk.length;
      final elapsed = _firstAudioChunkTime != null
          ? DateTime.now().difference(_firstAudioChunkTime!).inMilliseconds
          : 0;
      _log.fine('Audio chunk fed: ${chunk.length} bytes '
          '(total $_audioBytesFed, elapsed ${elapsed}ms)');
    } catch (e, st) {
      _log.severe('Failed to feed audio chunk to SoLoud', e, st);
    }
  }

  /// Called when the SoLoud stream has finished playing. Cleans up the stream
  /// and transitions the chat back to idle.
  void _finalizeSpeaking() {
    final elapsed = _firstAudioChunkTime != null
        ? DateTime.now().difference(_firstAudioChunkTime!).inMilliseconds
        : 0;
    _stopAudioStream();
    if (state.sessionState == ChatSessionState.speaking) {
      state = state.copyWith(sessionState: ChatSessionState.idle);
      _pushWidgetState('idle');
      _log.info('Audio playback finished — transitioned to idle '
          '(total audio duration ${elapsed}ms)');
    }
  }

  /// Stop the active SoLoud stream and release its resources. Safe to call
  /// multiple times; used by barge-in, stopListening, endSession, and dispose.
  void _stopAudioStream() {
    _audioStreamFinishedSub?.cancel();
    _audioStreamFinishedSub = null;
    if (_soloudHandle != null) {
      try {
        // Only stop the handle if it is still valid. If the stream has
        // already finished naturally, stop() can hang on an invalid handle.
        if (SoLoud.instance.getIsValidVoiceHandle(_soloudHandle!)) {
          SoLoud.instance.stop(_soloudHandle!);
        }
      } catch (e) {
        _log.fine('Error stopping SoLoud handle: $e');
      }
      _soloudHandle = null;
    }
    if (_soloudAudioSource != null) {
      try {
        // Signal end of data in case the stream is still active, then
        // dispose the source to free native resources.
        SoLoud.instance.setDataIsEnded(_soloudAudioSource!);
        SoLoud.instance.disposeSource(_soloudAudioSource!);
      } catch (e) {
        _log.fine('Error disposing SoLoud source: $e');
      }
      _soloudAudioSource = null;
    }
    _isAudioStreamActive = false;
    _audioBytesFed = 0;
    _firstAudioChunkTime = null;
  }

  /// Persist a chat message to the database (fire-and-forget).
  void _persistMessage(ChatMessage message) {
    try {
      final db = _ref.read(databaseProvider);
      db.saveMessage(
        content: message.text,
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
    // Fire-and-forget teardown — endSession() is async but dispose() is
    // synchronous. We cancel subscriptions synchronously to prevent
    // leaks, then let endSession() finish in the background.
    unawaited(endSession());
    super.dispose();
  }
}

/// Riverpod provider for chat state
final chatProvider =
    StateNotifierProvider<ChatNotifier, ChatSessionData>((ref) {
  return ChatNotifier(ref);
});