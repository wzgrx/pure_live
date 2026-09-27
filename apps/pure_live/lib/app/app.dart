import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pure_live_app/app/appearance.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/network.dart';
import 'package:pure_live_app/core/recording.dart';
import 'package:pure_live_app/core/share_intake.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/iptv/iptv_providers.dart';
import 'package:pure_live_app/features/iptv/iptv_share.dart';
import 'package:pure_live_app/features/system/mini_player_host.dart';
import 'package:pure_live_app/features/system/system_integration.dart';
import 'package:pure_live_app/l10n/strings.dart';

/// The root widget.
class PureLiveApp extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref
      ..watch(shareIntakeProvider)
      // Start the recorder so crash recovery and resumable tasks run at launch.
      ..watch(recordManagerProvider)
      ..watch(iptvShareIntakeProvider)
      ..watch(iptvAutoSyncProvider)
      ..watch(systemIntegrationProvider)
      // Known before the first room opens (Q-2); listened, so a network
      // change does not rebuild the app.
      ..listen(networkKindProvider, (_, _) {});
    final (light, dark, mode) = themesFor(ref.watch(themeModeSetting), pureBlack: ref.watch(pureBlackSetting));
    return MaterialApp.router(
      title: S.appName,
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: mode,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final scale = media.textScaler.scale(1) * ref.watch(textScaleSetting);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(scale)),
          // The in-app mini window floats above every page (F-PIP-03).
          child: MiniPlayerHost(child: child!),
        );
      },
    );
  }
}
