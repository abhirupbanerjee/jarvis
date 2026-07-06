// lib/services/error_handler.dart — Centralized Error Taxonomy
//
// All errors across the system fall into one of these categories.
// Each has a distinct user experience and recovery strategy.

import 'package:logging/logging.dart';

final _log = Logger('ErrorHandler');

/// Error categories for routing to appropriate recovery paths
enum ErrorCategory {
  /// No connectivity, DNS failure, timeout
  network,

  /// API key invalid, API key expired/revoked
  auth,

  /// Gemini rate limit (429), Tavily quota exceeded, model overloaded
  api,

  /// Permission denied (alarm), app not found, invalid args from LLM
  tool,

  /// Mic permission denied, audio format mismatch, buffer underrun
  audio,

  /// Drift database corruption, migration failure, disk full
  data,

  /// Unknown / unclassified error
  unknown,
}

/// Structured error information
class JarvisError {
  final ErrorCategory category;
  final String technicalMessage;
  final String userFacingMessage;
  final Object? originalError;
  final StackTrace? stackTrace;

  const JarvisError({
    required this.category,
    required this.technicalMessage,
    required this.userFacingMessage,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => 'JarvisError(category: $category, message: $technicalMessage)';
}

/// Centralized error handler that categorizes errors and routes
/// to the appropriate recovery path.
class ErrorHandler {
  /// Categorize an error and return a structured JarvisError
  JarvisError categorize(Object error, StackTrace stack) {
    final category = _categorize(error);
    final userMessage = _userFacingMessage(category, error);

    _log.severe('[$category] $error', error, stack);

    return JarvisError(
      category: category,
      technicalMessage: error.toString(),
      userFacingMessage: userMessage,
      originalError: error,
      stackTrace: stack,
    );
  }

  ErrorCategory _categorize(Object error) {
    final message = error.toString().toLowerCase();

    // Network errors
    if (message.contains('socketexception') ||
        message.contains('timeout') ||
        message.contains('dns') ||
        message.contains('connection refused') ||
        message.contains('no internet') ||
        message.contains('network')) {
      return ErrorCategory.network;
    }

    // Auth errors
    if (message.contains('401') ||
        message.contains('403') ||
        message.contains('unauthorized') ||
        message.contains('api key') ||
        message.contains('invalid key') ||
        message.contains('auth')) {
      return ErrorCategory.auth;
    }

    // API errors (rate limits, quotas)
    if (message.contains('429') ||
        message.contains('rate limit') ||
        message.contains('quota') ||
        message.contains('overloaded') ||
        message.contains('503')) {
      return ErrorCategory.api;
    }

    // Tool errors
    if (message.contains('permission denied') ||
        message.contains('permission') ||
        message.contains('not found') ||
        message.contains('not installed')) {
      return ErrorCategory.tool;
    }

    // Audio errors
    if (message.contains('microphone') ||
        message.contains('audio') ||
        message.contains('buffer') ||
        message.contains('pcm')) {
      return ErrorCategory.audio;
    }

    // Data errors
    if (message.contains('sqlite') ||
        message.contains('database') ||
        message.contains('drift') ||
        message.contains('disk full') ||
        message.contains('migration')) {
      return ErrorCategory.data;
    }

    return ErrorCategory.unknown;
  }

  String _userFacingMessage(ErrorCategory category, Object error) {
    return switch (category) {
      ErrorCategory.network =>
        "I'm having trouble connecting. Check your network.",
      ErrorCategory.auth =>
        "API key error. Check your configuration.",
      ErrorCategory.api =>
        "I'm a bit busy right now. Try again in a moment.",
      ErrorCategory.tool =>
        "I couldn't complete that action. Check your permissions.",
      ErrorCategory.audio =>
        "I can't access the microphone. Check permissions.",
      ErrorCategory.data =>
        "I had trouble saving that. Try again?",
      ErrorCategory.unknown =>
        "Something went wrong. Please try again.",
    };
  }
}
