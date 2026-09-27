import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pure_live_app/app/app.dart';
import 'package:pure_live_app/core/desktop_window.dart';
import 'package:pure_live_app/core/recording.dart';
import 'package:pure_live_app/core/secrets.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Settings and secrets are in memory before the first frame (REG-STORE-001).
  final root = await getApplicationSupportDirectory();
  final store = await LiveStore.open(root.path);
  final secrets = await openSecretStore(root.path);
  final recordPaths = await RecordPaths.resolve(root.path);
  await initDesktopWindow(store.settings);
  runApp(
    ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        recordPathsProvider.overrideWithValue(recordPaths),
        secretStoreProvider.overrideWithValue(secrets),
        // Adapters read the user's platform cookies from the encrypted store.
        cookieVaultProvider.overrideWithValue(StoreCookieVault(secrets)),
      ],
      child: const PureLiveApp(),
    ),
  );
}
