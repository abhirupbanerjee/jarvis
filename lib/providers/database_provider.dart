// lib/providers/database_provider.dart — Database Riverpod Provider

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';

/// Singleton AppDatabase instance
final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});
