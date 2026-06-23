import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/app.dart';
import 'app/di.dart';
import 'app/router.dart';
import 'core/storage/secure_store.dart';
import 'features/permissions/data/consent_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await configureDependencies();
  runApp(OwnPayConsoleApp(router: buildRouter(initialLocation: await _resolveStart())));
}

/// Resolves the start route once at launch:
/// unpaired → pair · paired but onboarding not finished → disclosure · otherwise → home.
Future<String> _resolveStart() async {
  final bool paired = await sl<SecureStore>().isPaired();
  if (!paired) {
    return '/pair';
  }
  final bool disclosureDone = await sl<ConsentStore>().isDisclosureCompleted();
  return disclosureDone ? '/' : '/disclosure';
}
