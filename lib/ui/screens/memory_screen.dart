// lib/ui/screens/memory_screen.dart — Memory Viewer & Management
//
// Browse, search, and delete stored user memories.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../providers/database_provider.dart';

class MemoryScreen extends ConsumerStatefulWidget {
  const MemoryScreen({super.key});

  @override
  ConsumerState<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends ConsumerState<MemoryScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final db = ref.watch(databaseProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Stored Memories',
          style: TextStyle(
            color: theme.colorScheme.primary,
            letterSpacing: 2,
            fontWeight: FontWeight.w300,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: FutureBuilder<List<UserMemory>>(
        future: db.getAllMemories(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Failed to load memories',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            );
          }

          final memories = snapshot.data ?? [];

          if (memories.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.memory,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No memories stored yet',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ask J.A.R.V.I.S. to remember something',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withAlpha(128),
                    ),
                  ),
                ],
              ),
            );
          }

          // Group by category
          final grouped = <String, List<UserMemory>>{};
          for (final m in memories) {
            grouped.putIfAbsent(m.category, () => []).add(m);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: grouped.entries.map((entry) {
              return _CategorySection(
                category: entry.key,
                memories: entry.value,
                db: db,
                onDeleted: () => setState(() {}),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final String category;
  final List<UserMemory> memories;
  final AppDatabase db;
  final VoidCallback onDeleted;

  const _CategorySection({
    required this.category,
    required this.memories,
    required this.db,
    required this.onDeleted,
  });

  IconData _categoryIcon(String cat) {
    return switch (cat) {
      'preference' => Icons.tune,
      'fact' => Icons.lightbulb_outline,
      'schedule' => Icons.schedule,
      'contact' => Icons.person_outline,
      _ => Icons.label_outline,
    };
  }

  void _confirmDelete(BuildContext context, UserMemory memory) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Memory'),
        content: Text('Delete "${memory.key}"?\n\n${memory.value}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await db.deleteMemory(memory.category, memory.key);
              if (ctx.mounted) Navigator.pop(ctx);
              onDeleted();
            },
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category header
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(
                _categoryIcon(category),
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                category.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(${memories.length})',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        // Memory cards
        ...memories.map((m) => Card(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  m.key,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  m.value,
                  style: theme.textTheme.bodySmall,
                ),
                trailing: IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error.withAlpha(180),
                    size: 20,
                  ),
                  onPressed: () => _confirmDelete(context, m),
                ),
              ),
            )),
        const SizedBox(height: 16),
      ],
    );
  }
}
