import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Scans the admin-panel pairing QR (`{"server_url":"...","otp":"..."}`) and pops the parsed
/// `{server_url, otp}` back to the pairing screen. Camera permission is requested by mobile_scanner.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan pairing QR')),
      body: MobileScanner(onDetect: _onDetect),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || !mounted) return;
    for (final Barcode barcode in capture.barcodes) {
      final String? raw = barcode.rawValue;
      if (raw == null) continue;
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
}
