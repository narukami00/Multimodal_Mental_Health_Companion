import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/app_shell/app_shell.dart';

void main() {
  runApp(const SolaceApp());
}

class SolaceApp extends StatelessWidget {
  const SolaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solace',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AppShell(),
    );
  }
}

// Kept as an alias while the bootstrap test and early integrations migrate.
typedef MainApp = SolaceApp;
