import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../../../core/services/session_status.dart';
import '../../../shared/theme/app_theme.dart';
import '../data/device_repository.dart';
import 'pairing_cubit.dart';
import 'qr_scan_screen.dart';

/// Device pairing (mockup #2): scan the admin QR or enter the server URL + 6-digit code manually,
/// then "Verify & Link".
class PairingScreen extends StatelessWidget {
  const PairingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PairingCubit>(
      create: (_) => PairingCubit(sl<DeviceRepository>(), sl<SessionStatus>()),
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
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              children: <Widget>[
                const SizedBox(height: 16),
                const Text(
                  'Pair Device',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textHi, fontSize: 26, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Scan the QR code from your OwnPay Web Panel to securely link this device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 28),
                _QrTarget(onTap: busy ? null : _scan),
                const SizedBox(height: 24),
                const _OrDivider(),
                const SizedBox(height: 24),
                TextField(
                  controller: _serverCtrl,
                  enabled: !busy,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  style: const TextStyle(color: AppColors.textHi),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.dns_outlined),
                    hintText: 'https://pay.example.com',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _otpCtrl,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.textHi, letterSpacing: 2),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                    hintText: 'Pairing code',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _nameCtrl,
                  enabled: !busy,
                  style: const TextStyle(color: AppColors.textHi),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.smartphone_outlined),
                    hintText: 'Device name',
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: busy ? null : _submit,
                  child: busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrand),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text('Verify & Link'),
                            SizedBox(width: 8),
                            Icon(Icons.check, size: 18),
                          ],
                        ),
                ),
                const SizedBox(height: 8),
                if (context.canPop())
                  TextButton(
                    onPressed: busy ? null : () => context.pop(),
                    child: const Text('Back'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The dashed QR target box with a camera glyph — tap to open the scanner.
class _QrTarget extends StatelessWidget {
  const _QrTarget({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: AppColors.brand.withValues(alpha: 0.5),
            radius: 20,
          ),
          child: Container(
            height: 200,
            width: 200,
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: Icon(Icons.photo_camera_outlined, color: AppColors.brand, size: 44),
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontal "OR" divider.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Expanded(child: Divider(color: AppColors.outline)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('OR', style: AppTheme.overline.copyWith(color: AppColors.textMuted)),
        ),
        const Expanded(child: Divider(color: AppColors.outline)),
      ],
    );
  }
}

/// Paints a dashed rounded-rectangle border (Flutter has no built-in dashed border; this is a few lines
/// of native code rather than pulling in a dependency — per the dependency rule).
class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final RRect rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final Path path = Path()..addRRect(rrect);

    const double dash = 7;
    const double gap = 5;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dash),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
