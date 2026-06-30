import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

/// Scans the admin-panel pairing QR (`{"server_url":"...","otp":"..."}`) and pops the parsed
/// `{server_url, otp}` back to the pairing screen.
///
/// Uses the canonical `mobile_scanner` form where the [MobileScanner] widget owns its
/// [MobileScannerController]: the widget starts the camera exactly once (auto-start) and handles
/// app-lifecycle pause/resume itself. An earlier version created a controller AND called `start()`
/// manually while the widget also auto-started it — a double-start that surfaced as a generic
/// scanner error. Any camera/ML-Kit failure is rendered by [MobileScanner.errorBuilder] (including
/// the underlying native message) with a manual-entry fallback: the pairing screen always accepts a
/// typed URL + code, so the scanner is a convenience, never a hard dependency.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  // Guards against popping more than once when several frames decode the same QR in quick succession.
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled || !mounted) {
      return;
    }
    for (final Barcode barcode in capture.barcodes) {
      final String? raw = barcode.rawValue;
      if (raw == null) {
        continue;
      }
      final Map<String, String>? parsed = _tryParse(raw);
      if (parsed != null) {
        _handled = true;
        Navigator.of(context).pop(parsed);
        return;
      }
    }
  }

  Map<String, String>? _tryParse(String raw) {
    try {
      final Object? obj = jsonDecode(raw);
      if (obj is Map<String, dynamic>) {
        final Object? url = obj['server_url'];
        final Object? otp = obj['otp'];
        if (url is String && otp is String) {
          return <String, String>{'server_url': url, 'otp': otp};
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan pairing QR')),
      body: MobileScanner(
        fit: BoxFit.cover,
        onDetect: _onDetect,
        errorBuilder: (BuildContext context, MobileScannerException error) => _ScanError(error: error),
      ),
    );
  }
}

/// Graceful fallback shown when the camera/scanner can't start (permission denied, no camera, ML-Kit
/// init failure). Surfaces the underlying native message so a device-specific failure is diagnosable
/// rather than hidden behind a generic code, and always offers manual entry — pairing works without
/// the camera.
class _ScanError extends StatelessWidget {
  const _ScanError({required this.error});

  final MobileScannerException error;

  bool get _permissionDenied => error.errorCode == MobileScannerErrorCode.permissionDenied;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // The real cause (e.g. an ML Kit init NPE) is carried in errorDetails.message; the bare
    // errorCode alone is too coarse to act on.
    final String? detail = error.errorDetails?.message;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              _permissionDenied ? Icons.no_photography_outlined : Icons.qr_code_scanner,
              size: 40,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              _permissionDenied ? 'Camera permission needed' : 'Camera unavailable',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _permissionDenied
                  ? 'Allow camera access to scan the pairing QR, or go back and enter the server URL '
                      'and pairing code manually.'
                  : 'Could not start the scanner. Go back and enter the server URL and pairing code '
                      'manually instead.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (detail != null && detail.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
            const SizedBox(height: 16),
            if (_permissionDenied) ...<Widget>[
              FilledButton(
                onPressed: () => unawaited(openAppSettings()),
                child: const Text('Open settings'),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Enter code manually'),
            ),
          ],
        ),
      ),
    );
  }
}
