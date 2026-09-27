import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/appearance.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/recording.dart';
import 'package:pure_live_app/core/share_intake.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/core/tv.dart';
import 'package:pure_live_app/features/iptv/iptv_providers.dart';
import 'package:pure_live_app/features/iptv/iptv_share.dart';
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
      ..watch(iptvAutoSyncProvider);
    final tv = ref.watch(tvConfigProvider);
    final textScale = ref.watch(textScaleSetting);
    final (light, dark, mode) = themesFor(
      ref.watch(themeModeSetting),
      pureBlack: ref.watch(pureBlackSetting),
      tv: tv.enabled,
    );
    return MaterialApp.router(
      title: S.appName,
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: mode,
      routerConfig: ref.watch(routerProvider),
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
              child: child!,
            );
          },
        ),
      ),
    );
  }
}
