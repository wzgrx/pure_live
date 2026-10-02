import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/tv/tv_theme.dart';

/// Escape goes back one level on the TV interface (a keyboard on a box or a
/// computer); the remote's Back arrives as the system's back.
class TvBackIntent extends Intent {
  /// Creates the intent.
  const new();
}

/// What the whole TV interface sits in (below the app's theme, above the
/// navigator), the counterpart of pure_live_TV's app shell:
///
/// - directional navigation ([NavigationMode.directional]: disabled controls
///   stay reachable, sliders move only once selected);
/// - text lifted on panels below 1080 lines ([TvScale.legibilityLift]) on
///   top of the user's text size;
/// - the TV palette: the phone's dark colour roles from the app theme
///   ([TvTheme], docs/T18/T18a/T18a.2 c4; the app shows its dark theme on
///   the TV), whether focused items grow (`tvFocusZoom`), and the toast in
///   the TV's sizes (16, corners of 12, U.15a's toast);
/// - Escape as Back.
class TvAppFrame extends ConsumerWidget {
  /// Wraps [child].
  const new({required this.child, super.key});

  /// The navigator.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final lift = TvScale.legibilityLift(context);
    final theme = Theme.of(context);
    final palette = TvPalette.of(theme.colorScheme);
    final framed = MediaQuery(
      data: media.copyWith(
        navigationMode: NavigationMode.directional,
        textScaler: TextScaler.linear(media.textScaler.scale(1) * lift),
      ),
      child: Builder(
        builder: (context) {
          final scale = TvScale.of(context);
          return Theme(
            data: theme.copyWith(
              colorScheme: palette.scheme,
              snackBarTheme: theme.snackBarTheme.copyWith(
                behavior: SnackBarBehavior.floating,
                backgroundColor: palette.scheme.inverseSurface,
                contentTextStyle: scale.font(TvTextSize.body, color: palette.scheme.onInverseSurface),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(scale.px(TvRadius.card))),
                insetPadding: EdgeInsets.fromLTRB(scale.px(240), 0, scale.px(240), scale.px(48)),
              ),
            ),
            child: child,
          );
        },
      ),
    );
    return TvTheme(
      palette: palette,
      zoom: watchSetting(ref, Settings.tvFocusZoom),
      child: Shortcuts(
        shortcuts: const {SingleActivator(LogicalKeyboardKey.escape): TvBackIntent()},
        child: Actions(
          actions: {
            TvBackIntent: CallbackAction<TvBackIntent>(
              onInvoke: (_) {
                final navigator = AppNavigator.navigatorContext;
                if (navigator != null) Navigator.maybePop(navigator);
                return null;
              },
            ),
          },
          child: framed,
        ),
      ),
    );
  }
}
