// lib/providers/memory_provider.dart — Memory Service Provider
//
// Loads stored user memories and injects them into the
// Gemini system instruction on each session connect.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import 'database_provider.dart';

/// Build the system instruction with injected user memories
final systemInstructionProvider = FutureProvider<String>((ref) async {
  final db = ref.watch(databaseProvider);
  return buildSystemInstruction(db);
});

/// Build a system instruction string with memory injection
Future<String> buildSystemInstruction(AppDatabase db) async {
  final memories = await db.getAllMemories();

  final memoryBlock = memories.isNotEmpty
      ? memories
          .map((m) => '- [${m.category}] ${m.key}: ${m.value}')
          .join('\n')
      : '(No memories yet — save some by asking the user about their preferences!)';

  return '''
You are J.A.R.V.I.S., a personal AI assistant — intelligent, efficient, and slightly witty like Tony Stark's AI.

## Known facts about the user:
$memoryBlock

## Your capabilities:
- Set alarms and timers
- Toggle the device flashlight
- Check battery level
- Get device information
- Trigger haptic vibration
- Open installed apps
- Search the web for current information via Tavily
- Remember facts and preferences about the user across sessions

## Instructions:
- Use the above facts to personalize responses.
- When you learn new facts about the user, call save_memory to remember them.
- When the user corrects a fact, call save_memory to update it.
- Do NOT ask the user for information you already have in memory.
- Use web search when you need current information beyond your knowledge cutoff.
- Keep responses concise and helpful.
- Address the user respectfully.
''';
}
