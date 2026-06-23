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
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
