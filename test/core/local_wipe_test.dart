import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ownpay_console/core/config/app_config.dart';
import 'package:ownpay_console/core/storage/local_wipe.dart';
import 'package:ownpay_console/core/storage/secure_store.dart';

class _MockSecureStore extends Mock implements SecureStore {}

void main() {
  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('ownpay_wipe');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {
      // Best-effort temp cleanup.
    }
  });

  test('wipe clears all app Hive boxes and the secure store', () async {
    final Box<Object> queue = await Hive.openBox<Object>(AppConfig.boxSmsQueue);
    await queue.put(1, <String, dynamic>{'x': 1});
    final Box<Object> dash = await Hive.openBox<Object>(AppConfig.boxDashboardCache);
    await dash.put('snapshot', <String, dynamic>{'y': 2});

    final _MockSecureStore store = _MockSecureStore();
    when(() => store.clear()).thenAnswer((_) async {});

    await LocalWipe(store).wipe();

    expect(queue.isEmpty, isTrue);
    expect(dash.isEmpty, isTrue);
    verify(() => store.clear()).called(1);
  });
}
