// Smoke tests for J.A.R.V.I.S. Phase 1
//
// Validates core app bootstrap, auth flow, tool registry integrity,
// and critical tool executors.

import 'package:flutter_test/flutter_test.dart';

import 'package:jarvis/config/llm_config.dart';
import 'package:jarvis/providers/llm_provider.dart';
import 'package:jarvis/tools/tool_registry.dart';

void main() {
  group('LlmConfig', () {
    test('default values are set correctly', () {
      final config = LlmConfig(
        modelId: 'gemini-2.5-flash-native-audio-latest',
        temperature: 0.7,
        voice: 'Puck',
        apiKey: 'test-key',
      );

      expect(config.modelId, 'gemini-2.5-flash-native-audio-latest');
      expect(config.temperature, 0.7);
      expect(config.voice, 'Puck');
      expect(config.isValid, isTrue);
    });

    test('invalid config is detected', () {
      final config = LlmConfig(
        modelId: 'test',
        temperature: 0.5,
        voice: 'Puck',
        apiKey: '',
      );

      expect(config.isValid, isFalse);
    });

    test('placeholder API key is treated as invalid', () {
      final config = LlmConfig(
        modelId: 'test',
        temperature: 0.5,
        voice: 'Puck',
        apiKey: 'PLACEHOLDER_SET_YOUR_KEY_HERE',
      );

      expect(config.isValid, isFalse);
    });

    test('ephemeral token mode is valid without API key', () {
      final config = LlmConfig(
        modelId: 'test',
        temperature: 0.5,
        voice: 'Puck',
        apiKey: '',
        tokenEndpoint: 'https://example.com/api/token',
        tokenAuthSecret: 'secret123',
      );

      expect(config.useEphemeralTokens, isTrue);
      expect(config.isValid, isTrue);
    });
  });

  group('Tool Registry', () {
    test('all 13 tools are registered', () {
      expect(toolRegistry.length, 13);
    });

    test('all tools have required fields', () {
      for (final tool in toolRegistry) {
        expect(tool.name.isNotEmpty, isTrue,
            reason: 'Tool ${tool.name} has empty name');
        expect(tool.description.isNotEmpty, isTrue,
            reason: 'Tool ${tool.name} has empty description');
        expect(tool.parameters, isNotEmpty,
            reason: 'Tool ${tool.name} has empty parameters');
      }
    });

    test('all tools can convert to declarations', () {
      for (final tool in toolRegistry) {
        final decl = tool.toDeclaration();
        expect(decl.name, tool.name);
        expect(decl.description, tool.description);
      }
    });

    test('tool names are unique', () {
      final names = toolRegistry.map((t) => t.name).toSet();
      expect(names.length, toolRegistry.length,
          reason: 'Duplicate tool names found');
    });

    test('set_timer tool validates invalid durations', () async {
      final timerTool = toolRegistry.firstWhere((t) => t.name == 'set_timer');

      final negativeResult = await timerTool.executor({
        'duration_seconds': -1,
      });
      expect(negativeResult['success'], isFalse);
      expect(negativeResult['error'], contains('positive'));

      final zeroResult = await timerTool.executor({
        'duration_seconds': 0,
      });
      expect(zeroResult['success'], isFalse);

      final tooLargeResult = await timerTool.executor({
        'duration_seconds': 100000,
      });
      expect(tooLargeResult['success'], isFalse);
      expect(tooLargeResult['error'], contains('max'));
    });
  });

  group('FunctionCall / FunctionResponse models', () {
    test('FunctionCall stores data correctly', () {
      const call = FunctionCall(
        id: 'call-123',
        name: 'tavily_search',
        args: {'query': 'test'},
      );

      expect(call.id, 'call-123');
      expect(call.name, 'tavily_search');
      expect(call.args['query'], 'test');
    });

    test('FunctionResponse stores data correctly', () {
      const response = FunctionResponse(
        id: 'call-123',
        name: 'tavily_search',
        result: {'answer': '42'},
      );

      expect(response.id, 'call-123');
      expect(response.name, 'tavily_search');
      expect(response.result['answer'], '42');
    });
  });
}
