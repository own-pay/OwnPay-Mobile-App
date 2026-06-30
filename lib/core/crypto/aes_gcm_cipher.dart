import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// AES-256-GCM cipher producing the exact envelope the OwnPay server expects.
///
/// Envelope layout (then base64-encoded), byte-compatible with the server's
/// `SmsParserService::decryptSmsPayload`:
///
///   ┌──────────────┬────────────────────┬──────────────┐
///   │  IV (12 B)   │     ciphertext     │   tag (16 B) │
///   └──────────────┴────────────────────┴──────────────┘
///
/// The per-device AES key (32 bytes) is issued at pairing and must never be logged or persisted
/// outside secure storage. A fresh random IV is generated for every message (IV reuse under one key
/// breaks GCM — never cache or reuse it).
class AesGcmCipher {
  AesGcmCipher();

  static const int ivLength = 12;
  static const int tagLength = 16;
  static const int keyLength = 32;

  final AesGcm _algorithm = AesGcm.with256bits();

  /// Encrypts [plaintext] (UTF-8) with [keyBytes] and returns the base64 envelope.
  ///
  /// Throws [ArgumentError] if the key is not exactly 32 bytes.
  Future<String> encryptToEnvelope({
    required String plaintext,
    required List<int> keyBytes,
  }) async {
    _assertKey(keyBytes);
    final secretKey = SecretKey(keyBytes);
    final nonce = _algorithm.newNonce(); // 12 bytes
    final box = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
      nonce: nonce,
    );

    final cipherText = box.cipherText;
    final tag = box.mac.bytes;
    final out = Uint8List(ivLength + cipherText.length + tagLength)
      ..setRange(0, ivLength, nonce)
      ..setRange(ivLength, ivLength + cipherText.length, cipherText)
      ..setRange(ivLength + cipherText.length, ivLength + cipherText.length + tagLength, tag);

    return base64.encode(out);
  }

  /// Decrypts a base64 envelope produced by [encryptToEnvelope] (or the server).
  ///
  /// Provided for completeness/round-trip testing; the device path is encrypt-only.
  /// Throws [FormatException] on a malformed envelope and [SecretBoxAuthenticationError]
  /// if the tag does not verify.
  Future<String> decryptFromEnvelope({
    required String envelopeBase64,
    required List<int> keyBytes,
  }) async {
    _assertKey(keyBytes);
    final bytes = base64.decode(envelopeBase64);
    if (bytes.length < ivLength + tagLength) {
      throw const FormatException('Envelope too short to contain IV + tag');
    }
    final nonce = bytes.sublist(0, ivLength);
    final tag = bytes.sublist(bytes.length - tagLength);
    final cipherText = bytes.sublist(ivLength, bytes.length - tagLength);

    final clear = await _algorithm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(tag)),
      secretKey: SecretKey(keyBytes),
    );
    return utf8.decode(clear);
  }

  /// Decodes a 64-char hex key (as issued at pairing) into 32 bytes.
  static List<int> keyFromHex(String hex) {
    final clean = hex.trim();
    if (clean.length != keyLength * 2) {
      throw ArgumentError('AES key hex must be ${keyLength * 2} characters');
    }
    final out = Uint8List(keyLength);
    for (var i = 0; i < keyLength; i++) {
      final byte = int.tryParse(clean.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) {
        throw ArgumentError('AES key hex contains a non-hex character');
      }
      out[i] = byte;
    }
    return out;
  }

  void _assertKey(List<int> keyBytes) {
    if (keyBytes.length != keyLength) {
      throw ArgumentError('AES key must be $keyLength bytes, got ${keyBytes.length}');
    }
  }
}
