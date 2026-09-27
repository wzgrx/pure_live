import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pure_live_app/app/app.dart';
import 'package:pure_live_app/core/desktop_window.dart';
import 'package:pure_live_app/core/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Settings must be in memory before the first frame (REG-STORE-001).
  final root = await getApplicationSupportDirectory();
  final store = await LiveStore.open(root.path);
  await initDesktopWindow(store.settings);
  runApp(ProviderScope(overrides: [storeProvider.overrideWithValue(store)], child: const PureLiveApp()));
}
