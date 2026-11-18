import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../crypto/spki_extractor.dart' as spki;
import '../storage/secure_store.dart';

/// Certificate pinning for **self-signed** OwnPay servers only.
///
/// Two different TLS modes ship in the app:
///
/// - **Standard mode** (the normal case): the app uses the platform's root CA store with full
///   hostname validation and never installs a custom certificate callback. If your server's
///   certificate is publicly trusted (e.g. Let's Encrypt), do nothing and it just works.
///
/// - **Pin mode**: for servers whose certificate is not publicly trusted (self-signed or a private
///   CA), the pairing QR can carry `{"spki": "<sha256>"}` where the fingerprint is the SHA-256 of
///   the certificate's Subject Public Key Info (SPKI). The user confirms the fingerprint on the
///   pairing screen and it is pinned on this device. Every subsequent TLS connection to that host
///   is validated **only** against the pin; the system trust store is ignored for that host.
///
/// SPKI pinning (rather than cert pinning) means a renewed certificate with the same key keeps
/// working — the common pattern for self-signed deployments. A different key is a hard failure,
/// surfacing as a TLS handshake error; the recovery path is re-pairing (which rotates the pin),
/// not a full wipe.
class CertificatePinner {
  CertificatePinner(this._store);

  final SecureStore _store;
  String? _fingerprint;
  String? _pinnedHost;

  /// Loads any previously-pinned fingerprint and host binding into memory
  /// (call at startup, before requests).
  Future<void> load() async {
    _fingerprint = await _store.readCertPin();
    _pinnedHost = _normalizeHost(await _store.readCertPinHost());
  }

  /// Binds the SPKI pin to [serverUrl]'s host. Called right after a successful pairing so a
  /// pinned server is never accepted on a different host; the pin and host are cleared together
  /// on wipe, keeping re-pair the re-pin path.
  Future<void> pinHost(String serverUrl) async {
    final String? host = _normalizeHost(serverUrl);
    if (host == null) return;
    _pinnedHost = host;
    await _store.setCertPinHost(host);
  }

  /// Explicitly pins [fingerprint] for [serverUrl]. Called from the pairing flow when the QR
  /// carries an `spki` fingerprint — the confirm dialog shows that fingerprint to the user.
  Future<void> pinFingerprint(String serverUrl, String fingerprint) async {
    _fingerprint = fingerprint;
    await _store.setCertPin(fingerprint);
    await pinHost(serverUrl);
  }

  static String? _normalizeHost(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final Uri? uri = Uri.tryParse(url.trim());
    final String host = (uri?.host ?? '').toLowerCase();
    return host.isEmpty ? null : host;
  }

  /// Removes the stored pin and host binding. Used by the "reset cert pin; re-pair" recovery path.
  Future<void> clearPin() async {
    _fingerprint = null;
    _pinnedHost = null;
    await _store.clearCertPin();
  }

  /// Testable pinning core: accepts the raw DER bytes of the presented certificate.
  /// Rejects: no pin configured, wrong host, SPKI mismatch — all hard failures.
  bool checkPin(List<int> der, [String host = '']) {
    if (_fingerprint == null) {
      return false; // no pin configured -> pinned mode refuses everything
    }
    final String? bound = _pinnedHost;
    if (bound != null && host.isNotEmpty && host.toLowerCase() != bound) {
      return false;
    }
    final String? presented = spki.spkiSha256Hex(Uint8List.fromList(der));
    return presented != null && presented == _fingerprint;
  }

  /// dio `validateCertificate` hook: trust only the pinned SPKI for the pinned host.
  /// A cert presented for a different host (same key material reused elsewhere) is rejected;
  /// a mismatched SPKI is rejected — the user must re-pair to rotate the pin.
  bool allows(X509Certificate? cert, [String host = '']) =>
      cert != null && checkPin(cert.der, host);
}
