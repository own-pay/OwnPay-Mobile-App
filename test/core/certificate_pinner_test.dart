import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ownpay_console/core/network/certificate_pinner.dart';
import 'package:ownpay_console/core/storage/secure_store.dart';

class _MockSecureStore extends Mock implements SecureStore {}

void main() {
  late _MockSecureStore store;

  setUp(() {
    store = _MockSecureStore();
    when(() => store.setCertPin(any())).thenAnswer((_) async {});
    when(() => store.readCertPin()).thenAnswer((_) async => null);
  });

  final List<int> certA = utf8.encode('cert-A-der');
  final List<int> certB = utf8.encode('cert-B-der');
  String fp(List<int> der) => sha256.convert(der).toString();

  test('TOFU: the first certificate is trusted and pinned', () {
    final CertificatePinner pinner = CertificatePinner(store);

    expect(pinner.checkDer(certA), isTrue);
    verify(() => store.setCertPin(fp(certA))).called(1);
  });

  test('the same cert stays trusted; a different cert is rejected', () {
    final CertificatePinner pinner = CertificatePinner(store);

    pinner.checkDer(certA); // pins A
    expect(pinner.checkDer(certA), isTrue);
    expect(pinner.checkDer(certB), isFalse);
  });

  test('a pin loaded from storage trusts the match and rejects others (no re-write)', () async {
    when(() => store.readCertPin()).thenAnswer((_) async => fp(certA));
    final CertificatePinner pinner = CertificatePinner(store);
    await pinner.load();

    expect(pinner.checkDer(certA), isTrue);
    expect(pinner.checkDer(certB), isFalse);
    verifyNever(() => store.setCertPin(any()));
  });
}
