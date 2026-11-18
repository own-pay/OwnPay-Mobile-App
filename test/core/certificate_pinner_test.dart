import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ownpay_console/core/network/certificate_pinner.dart';
import 'package:ownpay_console/core/storage/secure_store.dart';

class _MockSecureStore extends Mock implements SecureStore {}

void main() {
  late _MockSecureStore store;

  // Real self-signed certificate generated for tests (CN=ownpay-test.example.com).
  // SPKI SHA-256 of this certificate is EXACTLY the following constant, computed by openssl:
  //   openssl x509 -pubkey -noout -in cert.pem | openssl pkey -pubout -outform DER | sha256sum
  final Uint8List der = base64.decode('MIIDJTCCAg2gAwIBAgIUYEV1dPJMJLYdi5qUPnSmMM6S8WgwDQYJKoZIhvcNAQELBQAwIjEgMB4GA1UEAwwXb3ducGF5LXRlc3QuZXhhbXBsZS5jb20wHhcNMjYxMTE3MjEwMDM5WhcNMzYxMTE0MjEwMDM5WjAiMSAwHgYDVQQDDBdvd25wYXktdGVzdC5leGFtcGxlLmNvbTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOUrGs+Fxh8aflFc5p8f+D22gJ+lRmtZFvAwU23h8adYFEbshKGxgCbFMGfX//GJoqXZYjx8YXCDKJeg8siuzt4DDVUMypbX0sLhONJ5Q3XUgk2GR/TPYMmCkmPwTyfYxvht2SFZZ1Ab8t7r6TofuBhUMvgxyr4j6JvuqfNXHtmHPgb9IATaIoaLHjgppoyKxeuCX9FAcW0x1kAdwwUYPstEoQlrCwwkVh2E/qN5JAf1fm27j2ZoPhe8CO/9R8Kw70bnOE9jD5dQHM5Ib57bXSTo7mEEx+RhOYqYCcvalX7Oz6v6aTfSha8CiyoNNflpStRYvNTBHdmatdUcXAHM+msCAwEAAaNTMFEwHQYDVR0OBBYEFMFrh3oQdqBnwoMpGeeMukUPFG0qMB8GA1UdIwQYMBaAFMFrh3oQdqBnwoMpGeeMukUPFG0qMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBACVjPC5V2KVw0iRl9EIJATlTObaQqbcizDPbKqUY8dPBRa9zu+mD/QaHKrpWPrVKDPVQhvb04U7ZvqCHHE1Ix745rNjDYbKMlVSoWz3X4AImil65cghw9LLIUCN7nkpakyWPM6Romx3QTJSHvE5+pJdm5SjhEvXeot2SMPISz4xhG8WKUAYVrrsqAm6Hp21GZC7izjcXY9ZyfexGHEruK+8CUbDPkIn6rzQCGhxhHwGqJi8G5zLJUDeuDzxX1dc+Sep4OBX/AFSZM641RuckWsXXx2/HswG8OovWtC69FCgCmK9U+LqT18QKb/4wXntlEx+HiaJFLtvaWdMkAmm3G+k=');
  const String spkiHex =
      '2bde1d71ced9205909d86063f663c014ff6307ef02caad8002ac2e02a0dc2085';

  setUp(() {
    store = _MockSecureStore();
    when(() => store.setCertPin(any())).thenAnswer((_) async {});
    when(() => store.setCertPinHost(any())).thenAnswer((_) async {});
    when(() => store.clearCertPin()).thenAnswer((_) async {});
    when(() => store.readCertPin()).thenAnswer((_) async => null);
    when(() => store.readCertPinHost()).thenAnswer((_) async => null);
  });

  test('no pin stored: every certificate is rejected (fail closed)', () {
    final CertificatePinner pinner = CertificatePinner(store);
    expect(pinner.checkPin(der, 'pay.example.com'), isFalse);
  });

  test('pinHost + pinFingerprint pin the server and host', () async {
    final CertificatePinner pinner = CertificatePinner(store);
    await pinner.pinFingerprint('https://pay.example.com', spkiHex);

    expect(pinner.checkPin(der, 'pay.example.com'), isTrue);
    verify(() => store.setCertPin(spkiHex)).called(1);
    verify(() => store.setCertPinHost('pay.example.com')).called(1);
  });

  test('a different certificate is rejected', () async {
    final CertificatePinner pinner = CertificatePinner(store);
    await pinner.pinFingerprint('https://pay.example.com', spkiHex);

    // Same key would produce the same SPKI; a *different* cert with different key bytes is rejected.
    expect(pinner.checkPin(const <int>[1, 2, 3, 4], 'pay.example.com'), isFalse);
  });

  test('the pinned host gate rejects the pin on another host', () async {
    final CertificatePinner pinner = CertificatePinner(store);
    await pinner.pinFingerprint('https://pay.example.com', spkiHex);

    expect(pinner.checkPin(der, 'other.example.com'), isFalse);
  });

  test('pin loaded from storage trusts exactly the pinned key', () async {
    when(() => store.readCertPin()).thenAnswer((_) async => spkiHex);
    when(() => store.readCertPinHost()).thenAnswer((_) async => 'pay.example.com');
    final CertificatePinner pinner = CertificatePinner(store);
    await pinner.load();

    expect(pinner.checkPin(der, 'pay.example.com'), isTrue);
    verifyNever(() => store.setCertPin(any()));
  });

  test('clearPin drops fingerprint and host', () async {
    final CertificatePinner pinner = CertificatePinner(store);
    await pinner.pinFingerprint('https://pay.example.com', spkiHex);
    await pinner.clearPin();

    expect(pinner.checkPin(der, 'pay.example.com'), isFalse);
    verify(() => store.clearCertPin()).called(1);
  });
}
