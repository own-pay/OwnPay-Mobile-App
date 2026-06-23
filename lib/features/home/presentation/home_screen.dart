import 'package:flutter/material.dart';

/// First-run / unpaired home. Pairing, the dashboard, and SMS monitoring are wired in subsequent
/// build increments (see docs/ROADMAP.md). Until a device is paired, this informational state is
/// shown — it accurately reflects that the app has no server to talk to yet.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('OwnPay Console')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.verified_user_outlined, size: 48, color: scheme.primary),
              const SizedBox(height: 16),
              Text(
                'Confirm payments automatically',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'OwnPay Console reads your bank/MFS receipt SMS on-device, keeps OTPs and personal '
                'messages private, and sends only confirmed payments to your own OwnPay server.',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.link_off, color: scheme.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('Not paired', style: theme.textTheme.titleMedium),
                            const SizedBox(height: 2),
                            Text(
                              'Pair this device from your OwnPay admin panel to begin monitoring.',
                              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
