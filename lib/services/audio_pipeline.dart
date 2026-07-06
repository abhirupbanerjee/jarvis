// lib/services/audio_pipeline.dart — Voice Pipeline
//
// Manages microphone capture via the `record` package and streams
// PCM16 audio directly to the Gemini Live provider WebSocket.
// Gemini's server-side VAD handles speech detection and turn management.

import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:record/record.dart';

import '../providers/llm_provider.dart';

final _log = Logger('AudioPipeline');

/// States for the audio pipeline
enum AudioPipelineState {
  idle,
  initializing,
  listening,
  stopping,
  error,
}

class AudioPipeline {
  final AudioRecorder _recorder = AudioRecorder();
  final LlmProvider _llmProvider;

  // State
  AudioPipelineState _state = AudioPipelineState.idle;
  StreamSubscription<Uint8List>? _audioSubscription;

  // Callbacks
  void Function(AudioPipelineState state)? onStateChanged;
  void Function(Object error)? onError;

  AudioPipeline({required this._llmProvider});

  AudioPipelineState get state => _state;

  /// Start capturing audio and streaming to Gemini Live
  Future<void> startListening() async {
    if (_state == AudioPipelineState.listening) return;

    _setState(AudioPipelineState.initializing);
    _log.info('startListening: checking mic permission...');

    try {
      // Check microphone permission
      final hasPermission = await _recorder.hasPermission();
      _log.info('startListening: hasPermission=$hasPermission');
      if (!hasPermission) {
        _setState(AudioPipelineState.error);
        _log.warning('Microphone permission denied');
        onError?.call(Exception('Microphone permission denied'));
        return;
      }

      // Start recording stream — 16kHz PCM16 mono
      _log.info('startListening: calling _recorder.startStream()...');
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _log.info('startListening: stream obtained, setting up listener');

      _setState(AudioPipelineState.listening);
      _log.info('Audio recording started');

      // Stream audio frames to Gemini Live
      _audioSubscription = stream.listen(
        (audioFrame) {
          _llmProvider.sendAudio(audioFrame);
        },
        onError: (error) {
          _log.severe('Audio stream error: $error');
          _setState(AudioPipelineState.error);
          onError?.call(error);
        },
        onDone: () {
          _log.info('Audio stream ended');
          _setState(AudioPipelineState.idle);
        },
      );
      _log.info('startListening: listener attached, streaming audio');
    } catch (e) {
      _log.severe('Failed to start audio recording: $e');
      _setState(AudioPipelineState.error);
      onError?.call(e);
    }
  }

  /// Stop capturing audio
  Future<void> stopListening() async {
    if (_state != AudioPipelineState.listening) return;

    _setState(AudioPipelineState.stopping);

    await _audioSubscription?.cancel();
    _audioSubscription = null;

    try {
      await _recorder.stop();
      _log.info('Audio recording stopped');
    } catch (e) {
      _log.warning('Error stopping recorder: $e');
    }

    _setState(AudioPipelineState.idle);
  }

  void _setState(AudioPipelineState newState) {
    _state = newState;
    onStateChanged?.call(newState);
  }

  /// Clean up all resources
  Future<void> dispose() async {
    await stopListening();
    _recorder.dispose();
  }
}
