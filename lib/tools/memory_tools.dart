// lib/tools/memory_tools.dart — User Memory Tool Definitions
//
// Tools for saving, recalling, and listing user memories.
// Uses Drift SQLite for persistent storage.

import '../data/database.dart';
import 'tool_registry.dart';

// Singleton database instance (initialized lazily)
AppDatabase? _db;
AppDatabase get database {
  _db ??= AppDatabase();
  return _db!;
}

/// Save a fact, preference, or information about the user
final saveMemoryTool = ToolDefinition(
  name: 'save_memory',
  description:
      'Save a fact, preference, or piece of information about the user. '
      'Use this when you learn something new about the user that should be '
      'remembered across sessions (e.g., their name, preferences, routines, important dates).',
  parameters: {
    'type': 'object',
    'properties': {
      'category': {
        'type': 'string',
        'enum': ['preference', 'fact', 'schedule', 'contact', 'other'],
        'description': 'Category of the memory',
      },
      'key': {
        'type': 'string',
        'description':
            'Short identifier (e.g., "coffee", "name", "morning_routine")',
      },
      'value': {
        'type': 'string',
        'description': 'The information to remember',
      },
    },
    'required': ['category', 'key', 'value'],
  },
  executor: (args) async {
    await database.upsertMemory(
      category: args['category'] as String,
      key: args['key'] as String,
      value: args['value'] as String,
    );
    return {
      'success': true,
      'saved': '${args['category']}/${args['key']}',
    };
  },
);

/// Look up stored information about the user
final recallMemoryTool = ToolDefinition(
  name: 'recall_memory',
  description:
      'Look up stored information about the user by category or keyword.',
  parameters: {
    'type': 'object',
    'properties': {
      'category': {
        'type': 'string',
        'description': 'Filter by category (optional)',
      },
      'keyword': {
        'type': 'string',
        'description': 'Search keyword (optional)',
      },
    },
  },
  executor: (args) async {
    final results = await database.queryMemories(
      category: args['category'] as String?,
      keyword: args['keyword'] as String?,
    );
    return {
      'memories': results
          .map((m) => {
                'category': m.category,
                'key': m.key,
                'value': m.value,
                'updated': m.updatedAt.toIso8601String(),
              })
          .toList(),
      'count': results.length,
    };
  },
);

/// List all stored memories
final listMemoriesTool = ToolDefinition(
  name: 'list_memories',
  description:
      'List all stored memories about the user. Useful for reviewing what is known.',
  parameters: {
    'type': 'object',
    'properties': {},
  },
  executor: (args) async {
    final all = await database.getAllMemories();
    return {
      'count': all.length,
      'memories': all
          .map((m) => {
                'category': m.category,
                'key': m.key,
                'value': m.value,
              })
          .toList(),
    };
  },
);
