import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/appearance.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/network.dart';
import 'package:pure_live_app/core/recording.dart';
import 'package:pure_live_app/core/refresh_rate.dart';
import 'package:pure_live_app/core/share_intake.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/core/tv.dart';
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
    final tv = ref.watch(tvConfigProvider);
    final textScale = ref.watch(textScaleSetting);
    final dynamicColor = ref.watch(dynamicColorSetting) && !tv.enabled;
    final themeMode = ref.watch(themeModeSetting);
    final pureBlack = ref.watch(pureBlackSetting);
    final router = ref.watch(routerProvider);
    // Builds outside this build method (in DynamicColorBuilder): no ref here.
    Widget app(Color? seed) {
      final (light, dark, mode) = themesFor(themeMode, pureBlack: pureBlack, tv: tv.enabled, seed: seed);
      return MaterialApp.router(
        title: S.appName,
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        themeMode: mode,
        routerConfig: router,
        // TV mode: the 960×540 canvas, overscan margins and remote focus
        // (principles §5.3); off, only the scope that says so. The text scale
        // applies inside, on top of the canvas' media query.
        builder: (context, child) => TvRoot(
          config: tv,
          child: Builder(
            builder: (context) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(textScaler: TextScaler.linear(media.textScaler.scale(1) * textScale)),
                // The in-app mini window floats above every page (F-PIP-03).
                // Touches drive the refresh-rate hint (F-SET-08).
                child: RefreshRateScope(child: MiniPlayerHost(child: child!)),
              );
            },
          ),
        ),
      );
    }

    // Principles §2.2: wallpaper colours on Android 12+, the accent colour on
    // Windows; the brand theme elsewhere and while the platform answers.
    return dynamicColor ? DynamicColorBuilder(builder: (lightDynamic, _) => app(lightDynamic?.primary)) : app(null);
  }
}
