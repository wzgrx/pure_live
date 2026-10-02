import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Splash page (3.x `lib/modules/splash` and its route in `app_pages.dart`,
/// docs/A-界面设计/A06-首页和全局/A06.4-启动页).
///
/// Routes: `RoutePath.kSplash`.
///
/// The app's icon and "欢迎使用" fade and grow in over [animation] (0.4 s,
/// no overshoot, so they are whole when the page leaves; 3.x's 2 s fade left
/// at a third), 16 apart, over the theme's surface with a touch of the
/// primary container at the lower right (3.x: a fixed cyan gradient), and a
/// progress bar in the primary colour. Home replaces it after [duration]
/// (3.x: one second), or at once on a tap or any key, after waiting at most
/// [splashFollowWait] for the first follow check.
class SplashPage extends StatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, this.duration = const Duration(seconds: 1), super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  /// How long the page stays.
  final Duration duration;

  /// How long the icon and the text take to appear.
  static const Duration animation = Duration(milliseconds: 400);

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(vsync: this, duration: SplashPage.animation)
    ..forward();
  late final Animation<double> _fade = CurvedAnimation(parent: _animation, curve: Curves.decelerate);
  late final Animation<double> _scale = Tween<double>(
    begin: 0.9,
    end: 1,
  ).animate(CurvedAnimation(parent: _animation, curve: Curves.decelerate));
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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    unawaited(_leave());
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // A see-through status bar with icons for the page's brightness.
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
        statusBarColor: colors.surface.withValues(alpha: 0),
      ),
      child: Scaffold(
        backgroundColor: colors.surface,
        body: Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          child: GestureDetector(
            key: const ValueKey('splash'),
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_leave()),
            child: DecoratedBox(
              key: const ValueKey('splash-background'),
              decoration: BoxDecoration(
                // The mockup's 160°: from the top, slightly left, to the
                // bottom, slightly right.
                gradient: LinearGradient(
                  begin: const Alignment(-0.36, -1),
                  end: const Alignment(0.36, 1),
                  stops: const [0, 0.45, 1],
                  colors: [
                    colors.surface,
                    colors.surface,
                    Color.alphaBlend(colors.primaryContainer.withValues(alpha: dark ? 0.45 : 0.7), colors.surface),
                  ],
                ),
              ),
              child: SizedBox.expand(
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FadeTransition(
                        opacity: _fade,
                        child: ScaleTransition(
                          scale: _scale,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'assets/icons/icon.png',
                                key: const ValueKey('splash-logo'),
                                width: 150,
                                height: 150,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                i18n('welcome_use'),
                                style: context.textStyles.t20.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colors.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        key: const ValueKey('splash-progress'),
                        width: 200,
                        child: LinearProgressIndicator(
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(2),
                          color: colors.primary,
                          backgroundColor: colors.primary.withValues(alpha: 0.15),
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
