import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ownpay_console/core/crypto/aes_gcm_cipher.dart';
import 'package:ownpay_console/core/storage/secure_store.dart';
import 'package:ownpay_console/features/audit/data/sms_body_revealer.dart';
import 'package:ownpay_console/features/sync/domain/queued_sms.dart';

import 'audit_fakes.dart';

class _MockSecureStore extends Mock implements SecureStore {}

/// 32-byte AES key as hex-64 (matches what pairing issues).
const String _keyHex = '0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20';
const String _otherKeyHex = '20191a1b1c1d1e1f10111213141516171808090a0b0c0d0e0102030405060708';

/// The owner-only "tap to reveal" path. It must decrypt a real envelope for display, and fail SAFELY
/// (return null, never throw or leak) for every error case — no plaintext ever reaches a log.
void main() {
  late FakeSmsQueueStore queue;
  late _MockSecureStore store;
  final AesGcmCipher cipher = AesGcmCipher();

  setUp(() {
    queue = FakeSmsQueueStore();
    store = _MockSecureStore();
    when(() => store.readAesKey()).thenAnswer((_) async => _keyHex);
  });

  SmsBodyRevealer build() => SmsBodyRevealer(queue, store, cipher);

  Future<String> envelopeFor(String body, {String keyHex = _keyHex}) =>
      cipher.encryptToEnvelope(plaintext: body, keyBytes: AesGcmCipher.keyFromHex(keyHex));

  test('reveals the decrypted body for a queued row (round-trip)', () async {
    const String body = 'You have received Tk 1,250.00 from 01712345678. TrxID BK82JD91A';
    final QueuedSms row = queue.seed(payload: await envelopeFor(body));

    expect(await build().reveal(row.localId), body);
  });

  test('returns null when no key is stored (unpaired)', () async {
    when(() => store.readAesKey()).thenAnswer((_) async => null);
    final QueuedSms row = queue.seed(payload: await envelopeFor('anything'));

    expect(await build().reveal(row.localId), isNull);
  });

  test('returns null when the row is gone (purged/cleared)', () async {
    expect(await build().reveal(4242), isNull);
  });

  test('returns null for a malformed envelope (no throw, no leak)', () async {
    final QueuedSms row = queue.seed(payload: 'not-a-valid-base64-envelope!!');

    expect(await build().reveal(row.localId), isNull);
  });

  test('returns null when the key does not match the envelope (GCM tag fails)', () async {
    final QueuedSms row = queue.seed(payload: await envelopeFor('secret body'));
    // The stored key differs from the one the envelope was sealed with → authentication fails.
    when(() => store.readAesKey()).thenAnswer((_) async => _otherKeyHex);

    expect(await build().reveal(row.localId), isNull);
  });
}
