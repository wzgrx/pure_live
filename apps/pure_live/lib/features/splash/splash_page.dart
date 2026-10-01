import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/startup.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

/// Where the app starts: the splash page when the setting `showSplashPage`
/// is on, else home (3.x `main.dart`: `initialRoute`). The app passes it to
/// `buildAppRouter(initialLocation: ...)`.
String splashInitialLocation(SettingsStore settings) =>
    settings.get(Settings.showSplashPage) ? RoutePath.kSplash : RoutePath.kInitial;

/// Splash page (3.x `lib/modules/splash` and its route in `app_pages.dart`).
///
/// Routes: `RoutePath.kSplash`.
///
/// The logo fades and grows in over the theme's colours with "welcome" and a
/// progress bar; home replaces it after [duration] (3.x: one second), or at
/// once on a tap, after waiting at most [splashFollowWait] for the first
/// follow check.
class SplashPage extends StatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, this.duration = const Duration(seconds: 1), super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  /// How long the page stays.
  final Duration duration;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();
  late final Animation<double> _fade = CurvedAnimation(parent: _animation, curve: Curves.easeIn);
  late final Animation<double> _scale = Tween<double>(
    begin: 0.8,
    end: 1,
  ).animate(CurvedAnimation(parent: _animation, curve: Curves.easeOutBack));
  Timer? _timer;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, () => unawaited(_leave()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_left || !mounted) return;
    _left = true;
    _timer?.cancel();
    // A short, bounded wait for the first follow check, so a fast network
    // opens home with the follows settled (3.x); slow platforms finish later.
    if (AppStartup.followCheck case final check?) {
      await Future.any([check, Future<void>.delayed(splashFollowWait)]);
    }
    if (mounted) AppNavigator.offAllNamed(RoutePath.kInitial);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      body: GestureDetector(
        key: const ValueKey('splash'),
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_leave()),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? [colors.surface, colors.surfaceContainer, colors.primaryContainer.withValues(alpha: 0.35)]
                  : [colors.surface, colors.primaryContainer.withValues(alpha: 0.6), colors.primaryContainer],
            ),
          ),
          child: SizedBox.expand(
            child: SafeArea(
              child: FadeTransition(
                opacity: _fade,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ScaleTransition(
                      scale: _scale,
                      child: Image.asset('assets/icons/icon.png', width: 132, height: 132),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      i18n('welcome_use'),
                      style: context.textStyles.t20.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(i18n('app_name'), style: context.textStyles.t13.copyWith(color: colors.onSurfaceVariant)),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: 180,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          minHeight: 4,
                          color: colors.primary,
                          backgroundColor: colors.primary.withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
