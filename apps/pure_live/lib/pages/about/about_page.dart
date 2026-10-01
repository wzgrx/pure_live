import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/about/release_history_view.dart';
import 'package:pure_live/pages/version/app_version.dart';
import 'package:pure_live/pages/version/update_feed.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

/// About and version history (3.x `lib/modules/about`).
///
/// Routes: `RoutePath.kAbout` ([AboutView]) and `RoutePath.kVersionHistory`
/// ([ReleaseHistoryView]).
class AboutPage extends StatelessWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  Widget build(BuildContext context) => switch (route.path) {
    RoutePath.kVersionHistory => const ReleaseHistoryView(),
    _ => const AboutView(),
  };
}

/// The app's logo, name and version, the update and history entries, the
/// licences, the project page and the project statement (3.x `AboutPage`).
class AboutView extends StatefulWidget {
  /// Creates the view.
  const new({super.key});

  @override
  State<AboutView> createState() => _AboutViewState();
}

class _AboutViewState extends State<AboutView> {
  bool _openingProject = false;

  Future<void> _openProject() async {
    if (_openingProject) return;
    _openingProject = true;
    try {
      final opened = await AppNavigator.openExternal(projectUrl);
      if (!opened) AppNavigator.toast(i18n('external_browser_not_opened'));
    } on Object {
      AppNavigator.toast(i18n('external_browser_not_opened'));
    } finally {
      _openingProject = false;
    }
  }

  void _openLicenses() => showLicensePage(
    context: context,
    applicationName: i18n('app_name'),
    applicationLegalese: i18n('about_legalese'),
    applicationVersion: appVersion,
    useRootNavigator: true,
    applicationIcon: Padding(
      padding: const EdgeInsets.all(12),
      child: Image.asset('assets/icons/icon.png', width: 60, height: 60),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mobile = MediaQuery.sizeOf(context).shortestSide < 600;
    final logoSize = mobile ? 80.0 : 96.0;
    return Scaffold(
      appBar: AppBar(title: Text(i18n('about'))),
      body: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: settingsContentMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 1000),
                      curve: Curves.elasticOut,
                      builder: (context, value, child) => Transform.scale(scale: value, child: child),
                      child: Container(
                        width: logoSize,
                        height: logoSize,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.08)),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withValues(alpha: 0.06),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Image.asset('assets/icons/icon.png', fit: BoxFit.contain),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    i18n('app_name'),
                    textAlign: TextAlign.center,
                    style: context.textStyles.t18.copyWith(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'v$appVersion',
                        key: const ValueKey('about-version'),
                        style: context.textStyles.t11.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  context.buildGroupTitle(i18n('about')),
                  const SizedBox(height: 8),
                  context.buildModernCard([
                    context.buildTile(
                      icon: Icons.system_update_alt_rounded,
                      title: i18n('online_update'),
                      subtitle: i18n('about_update_subtitle'),
                      onTap: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kVersionPage)),
                    ),
                    context.buildTile(
                      icon: Icons.history_rounded,
                      title: i18n('history'),
                      subtitle: i18n('history_desc'),
                      onTap: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kVersionHistory)),
                    ),
                    context.buildTile(icon: Icons.policy_outlined, title: i18n('license'), onTap: _openLicenses),
                  ]),
                  const SizedBox(height: 24),
                  context.buildGroupTitle(i18n('project')),
                  const SizedBox(height: 8),
                  context.buildModernCard([
                    context.buildTile(
                      icon: Icons.code_rounded,
                      title: i18n('project_page'),
                      subtitle: projectUrl.toString(),
                      isLong: true,
                      onTap: () => unawaited(_openProject()),
                    ),
                    context.buildTile(
                      icon: Icons.info_outline_rounded,
                      title: i18n('project_alert'),
                      subtitle: i18n('about_legalese'),
                      isLong: true,
                      iconColor: theme.colorScheme.error,
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
