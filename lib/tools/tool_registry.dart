// lib/tools/tool_registry.dart — Tool Definition & Registry
//
// Every tool is defined with three parts: name, description,
// JSON Schema parameters, and an executor function.
// The registry is the canonical list of all Phase 1 tools.

import '../providers/llm_provider.dart';
import 'memory_tools.dart';
import 'native_tools.dart';
import 'tavily_tool.dart';

/// A tool definition that Gemini can call via function calling
class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parameters; // JSON Schema
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> args) executor;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    required this.executor,
  });

  /// Convert to the ToolDeclaration format used by LlmProvider
  ToolDeclaration toDeclaration() => ToolDeclaration(
        name: name,
        description: description,
        parameters: parameters,
      );
}

/// The canonical registry of all Phase 1 tools
final List<ToolDefinition> toolRegistry = [
  // P0: Time & Scheduling
  getCurrentTimeTool,
  setAlarmTool,
  setTimerTool,
  cancelAlarmTool,

  // P1: Device Hardware
  toggleFlashlightTool,
  getBatteryLevelTool,
  vibrateTool,
  getDeviceInfoTool,

  // P1: App Launch
  openAppTool,

  // P0: User Memory
  saveMemoryTool,
  recallMemoryTool,
  listMemoriesTool,

  // P0: External Services
  tavilySearchTool,
];
