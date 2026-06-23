import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../data/device_repository.dart';
import 'pairing_cubit.dart';
import 'qr_scan_screen.dart';

/// Device pairing: scan the admin QR or enter the server URL + 6-digit code manually.
class PairingScreen extends StatelessWidget {
  const PairingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PairingCubit>(
      create: (_) => PairingCubit(sl<DeviceRepository>()),
      child: const _PairingView(),
    );
  }
}

class _PairingView extends StatefulWidget {
  const _PairingView();

  @override
  State<_PairingView> createState() => _PairingViewState();
}

class _PairingViewState extends State<_PairingView> {
  final TextEditingController _serverCtrl = TextEditingController();
  final TextEditingController _otpCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController(text: 'My Android device');

  @override
  void dispose() {
    _serverCtrl.dispose();
    _otpCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    context.read<PairingCubit>().pair(
          serverUrl: _serverCtrl.text,
          otp: _otpCtrl.text,
          deviceName: _nameCtrl.text,
        );
  }

  Future<void> _scan() async {
    final Map<String, String>? result = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute<Map<String, String>>(builder: (_) => const QrScanScreen()),
    );
    if (!mounted || result == null) return;
    _serverCtrl.text = result['server_url'] ?? '';
    _otpCtrl.text = result['otp'] ?? '';
    _submit();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PairingCubit, PairingState>(
      listener: (BuildContext context, PairingState state) {
        if (state.status == PairingStatus.success) {
          // Freshly paired → show the prominent SMS disclosure before any permission request.
          context.go('/disclosure');
        } else if (state.status == PairingStatus.failure && state.error != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.error!)));
        }
      },
      builder: (BuildContext context, PairingState state) {
        final bool busy = state.status == PairingStatus.submitting;
        final ThemeData theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(title: const Text('Pair device')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: <Widget>[
                Text('Pair this device', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Scan the QR from your OwnPay admin panel, or enter the server URL and the '
                  '6-digit pairing code.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: busy ? null : _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR code'),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _serverCtrl,
                  enabled: !busy,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'https://pay.example.com',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _otpCtrl,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Pairing code',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameCtrl,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'Device name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy ? null : _submit,
                  child: busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Pair device'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
