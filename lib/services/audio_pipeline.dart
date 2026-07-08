// lib/services/audio_pipeline.dart — Voice Pipeline
//
// Manages microphone capture via the `record` package and streams
// PCM16 audio directly to the Gemini Live provider WebSocket.
// Gemini's server-side VAD handles speech detection and turn management.

import 'dart:async';
import 'dart:math';
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
  int _framesCaptured = 0;

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
          _framesCaptured++;
          // Periodic metering: log RMS level every 50 frames (~5s)
          // to help debug "no response" / silent-mic issues.
          if (_framesCaptured % 50 == 1) {
            final rms = _computeRms(audioFrame);
            final level = (rms / 32768 * 100).round().clamp(0, 100);
            _log.info('Mic meter: frame #$_framesCaptured, '
                '${audioFrame.length}B, level=$level%');
          }
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

  /// Compute RMS (root-mean-square) of PCM16 samples for metering.
  static double _computeRms(Uint8List pcm) {
    if (pcm.length < 2) return 0;
    final samples = pcm.length ~/ 2;
    var sumSquares = 0.0;
    for (int i = 0; i < samples; i++) {
      // PCM16 little-endian → signed 16-bit
      final lo = pcm[i * 2];
      final hi = pcm[i * 2 + 1];
      final sample = (hi << 8) | lo;
      final signed = sample > 32767 ? sample - 65536 : sample;
      sumSquares += signed * signed;
    }
    return sqrt(sumSquares / samples);
  }
}
