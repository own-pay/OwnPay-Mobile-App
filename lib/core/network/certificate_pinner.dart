import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../storage/secure_store.dart';

/// TOFU (trust-on-first-use) certificate pinner for the user's self-hosted server. Because each user's
/// server cert is unknown ahead of time, the first connection's leaf certificate is pinned (its SHA-256
/// fingerprint stored), and every later connection must present the exact same certificate. On server
/// cert rotation the user re-pairs after a wipe (which clears the pin). Used as dio's `validateCertificate`
/// hook in **release** builds only (debug keeps normal CA validation for local dev).
class CertificatePinner {
  CertificatePinner(this._store);

  final SecureStore _store;
  String? _fingerprint;

  /// Loads any previously-pinned fingerprint into memory (call at startup, before requests).
  Future<void> load() async {
    _fingerprint = await _store.readCertPin();
  }

  /// Sync pin check for a leaf certificate's DER bytes — the testable core. Pins the first cert seen,
  /// then requires an exact SHA-256 match.
  bool checkDer(List<int> der) {
    final String fingerprint = sha256.convert(der).toString();
    if (_fingerprint == null) {
      _fingerprint = fingerprint;
      unawaited(_store.setCertPin(fingerprint)); // persist TOFU pin; in-memory value already set
      return true;
    }
    return _fingerprint == fingerprint;
  }

  /// dio `validateCertificate` hook: trust only the pinned leaf certificate.
  bool allows(X509Certificate? cert) => cert != null && checkDer(cert.der);
}
