import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// - the TV palette from the app theme ([TvTheme]);
/// - Escape as Back.
class TvAppFrame extends StatelessWidget {
  /// Wraps [child].
  const new({required this.child, super.key});

  /// The navigator.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final lift = TvScale.legibilityLift(context);
    return MediaQuery(
      data: media.copyWith(
        navigationMode: NavigationMode.directional,
        textScaler: TextScaler.linear(media.textScaler.scale(1) * lift),
      ),
      child: TvTheme(
        palette: TvPalette.of(Theme.of(context).colorScheme),
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
            child: child,
          ),
        ),
      ),
    );
  }
}
