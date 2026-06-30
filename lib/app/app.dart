import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared/theme/app_theme.dart';

/// Root application widget, driven by a [GoRouter] built at startup with the paired/un-paired
/// start location.
class OwnPayConsoleApp extends StatelessWidget {
  const OwnPayConsoleApp({required this.router, super.key});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'OwnPay Console',
      debugShowCheckedModeBanner: false,
      // One cohesive dark theme, always — the console look is part of the product identity (DESIGN.md).
      // Both slots point at the dark theme so the frame never flashes light before themeMode is applied.
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
