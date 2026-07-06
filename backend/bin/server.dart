// backend/bin/server.dart — Ephemeral Token Server
//
// Minimal backend that generates short-lived Gemini Live API tokens.
// Deploy this to Cloud Run, a VPS, or run locally during development.
//
// The real GEMINI_API_KEY lives ONLY on this server — never in the client APK.

import 'dart:convert';
import 'dart:io';

import 'package:googleai_dart/googleai_dart.dart' as gai;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

// ── Configuration (from environment) ──

final _apiKey = Platform.environment['GEMINI_API_KEY'] ?? '';
final _sharedSecret = Platform.environment['TOKEN_SHARED_SECRET'] ?? '';
final _port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
final _modelId =
    Platform.environment['GEMINI_MODEL_ID'] ?? 'gemini-2.5-flash-native-audio-latest';

// ── Gemini client (server-side, holds real API key) ──

final _client = gai.GoogleAIClient(
  config: gai.GoogleAIConfig.googleAI(
    authProvider: gai.ApiKeyProvider(_apiKey),
  ),
);

// ── Router ──

final _router = Router()
  ..get('/health', (_) => Response.ok('OK'))
  ..post('/api/token', _handleTokenRequest);

/// POST /api/token
///
/// Headers:
///   `Authorization: Bearer <shared-secret>`
///
/// Response (200):
///   `{ "token": "<ephemeral-token-string>", "expiresAt": "<ISO8601>" }`
Future<Response> _handleTokenRequest(Request request) async {
  // Validate shared secret
  final authHeader = request.headers['authorization'] ?? '';
  if (_sharedSecret.isNotEmpty && authHeader != 'Bearer $_sharedSecret') {
    return Response.forbidden('Invalid authorization');
  }

  try {
    final expireTime = DateTime.now().add(const Duration(minutes: 30));
    final newSessionExpireTime = DateTime.now().add(const Duration(seconds: 60));

    final token = await _client.authTokens.create(
      authToken: gai.AuthToken(
        expireTime: expireTime,
        newSessionExpireTime: newSessionExpireTime,
        uses: 1,
        bidiGenerateContentSetup: gai.BidiGenerateContentSetup(
          model: 'models/$_modelId',
        ),
      ),
    );

    if (token.name == null || token.name!.isEmpty) {
      return Response.internalServerError(
        body: 'Failed to generate token',
      );
    }

    return Response.ok(
      jsonEncode({
        'token': token.name,
        'expiresAt': expireTime.toUtc().toIso8601String(),
        'model': _modelId,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    stderr.writeln('Token generation failed: $e');
    return Response.internalServerError(
      body: 'Token generation failed',
    );
  }
}

// ── Middleware ──

Middleware _corsMiddleware() {
  return (Handler handler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Authorization, Content-Type',
        });
      }
      final response = await handler(request);
      return response.change(headers: {
        'Access-Control-Allow-Origin': '*',
      });
    };
  };
}

// ── Entry Point ──

void main() async {
  if (_apiKey.isEmpty) {
    stderr.writeln('FATAL: GEMINI_API_KEY environment variable is required');
    exit(1);
  }

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsMiddleware())
      .addHandler(_router.call);

  final server = await io.serve(handler, InternetAddress.anyIPv4, _port);
  // ignore: avoid_print — server startup diagnostics
  print('Token server running on http://localhost:${server.port}');
  // ignore: avoid_print — server startup diagnostics
  print('Model: $_modelId');
  // ignore: avoid_print — server startup diagnostics
  print('Shared secret: ${_sharedSecret.isNotEmpty ? "configured" : "DISABLED (insecure)"}');
}
