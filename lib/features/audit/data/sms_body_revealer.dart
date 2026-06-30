import '../../../core/crypto/aes_gcm_cipher.dart';
import '../../../core/storage/secure_store.dart';
import '../../sync/domain/queued_sms.dart';
import '../../sync/domain/sms_queue_store.dart';

/// Decrypts a queued SMS envelope for **on-screen display to the device owner** (the "tap to reveal"
/// audit detail). This is the one sanctioned place the plaintext body is reconstructed on-device.
///
/// Privacy invariants (SECURITY.md §7/§9): the queue still stores only the AES-GCM ciphertext — nothing
/// here is ever persisted. The plaintext lives only in the returned String, in memory, for as long as
/// the detail sheet is on screen. It is **never logged** (CLAUDE.md §2.6) and never leaves the device.
/// The per-device key stays in the keystore via [SecureStore]; it is read into memory only for the
/// decrypt call. Decryption is authenticated (GCM tag), so a tampered envelope yields null, not garbage.
class SmsBodyRevealer {
  SmsBodyRevealer(this._queue, this._store, this._cipher);

  final SmsQueueStore _queue;
  final SecureStore _store;
  final AesGcmCipher _cipher;

  /// Returns the decrypted body for the queue row [localId], or null when it cannot be shown — the row
  /// is gone (purged), no key is stored (unpaired), or the envelope fails authentication/decoding.
  Future<String?> reveal(int localId) async {
    final String? keyHex = await _store.readAesKey();
    if (keyHex == null || keyHex.isEmpty) {
      return null; // unpaired / no key → nothing to decrypt
    }

    QueuedSms? row;
    for (final QueuedSms q in await _queue.all()) {
      if (q.localId == localId) {
        row = q;
        break;
      }
    }
    if (row == null) {
      return null;
    }

    try {
      final List<int> keyBytes = AesGcmCipher.keyFromHex(keyHex);
      return await _cipher.decryptFromEnvelope(
        envelopeBase64: row.encryptedPayload,
        keyBytes: keyBytes,
      );
    } on Object {
      // A bad key, malformed envelope, or failed GCM tag → we simply can't display it. Returning null
      // (rather than rethrowing or logging the payload) keeps the body off any log and surfaces a clean
      // "couldn't decrypt" state in the UI.
      return null;
    }
  }
}
