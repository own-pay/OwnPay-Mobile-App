import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ownpay_console/core/crypto/aes_gcm_cipher.dart';

void main() {
  final cipher = AesGcmCipher();
  // 32-byte (64 hex) deterministic test key.
  const keyHex = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
  final key = AesGcmCipher.keyFromHex(keyHex);

  group('AesGcmCipher', () {
    test('round-trips plaintext', () async {
      const msg = 'You have received Tk 1,500.00 from 017XXXXXXXX. TrxID 9F2K7Q1.';
      final envelope = await cipher.encryptToEnvelope(plaintext: msg, keyBytes: key);
      final back = await cipher.decryptFromEnvelope(envelopeBase64: envelope, keyBytes: key);
      expect(back, msg);
    });

    test('envelope is base64 of IV(12) + ciphertext + tag(16)', () async {
      const msg = 'hello'; // 5 UTF-8 bytes → ciphertext is 5 bytes in GCM (stream cipher)
      final envelope = await cipher.encryptToEnvelope(plaintext: msg, keyBytes: key);
      final bytes = base64.decode(envelope);
      expect(bytes.length, AesGcmCipher.ivLength + utf8.encode(msg).length + AesGcmCipher.tagLength);
    });

    test('uses a fresh random IV per call (no IV reuse)', () async {
      const msg = 'same message';
      final a = base64.decode(await cipher.encryptToEnvelope(plaintext: msg, keyBytes: key));
      final b = base64.decode(await cipher.encryptToEnvelope(plaintext: msg, keyBytes: key));
      final ivA = a.sublist(0, AesGcmCipher.ivLength);
      final ivB = b.sublist(0, AesGcmCipher.ivLength);
      expect(ivA, isNot(equals(ivB)));
    });

    test('tampered ciphertext fails authentication', () async {
      final envelope = await cipher.encryptToEnvelope(plaintext: 'secret', keyBytes: key);
      final bytes = base64.decode(envelope);
      bytes[AesGcmCipher.ivLength] = bytes[AesGcmCipher.ivLength] ^ 0xFF; // flip a ciphertext byte
      final tampered = base64.encode(bytes);
      expect(
        () => cipher.decryptFromEnvelope(envelopeBase64: tampered, keyBytes: key),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('rejects a non-32-byte key', () async {
      expect(
        () => cipher.encryptToEnvelope(plaintext: 'x', keyBytes: List.filled(16, 0)),
        throwsArgumentError,
      );
    });

    test('keyFromHex validates length and charset', () {
      expect(() => AesGcmCipher.keyFromHex('abcd'), throwsArgumentError);
      expect(() => AesGcmCipher.keyFromHex('zz' * 32), throwsArgumentError);
      expect(AesGcmCipher.keyFromHex(keyHex).length, 32);
    });
  });
}
