import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/version/app_version.dart';
import 'package:pure_live/features/version/update_feed.dart';
import 'package:pure_live/features/version/version_page.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

/// About (3.x `lib/modules/about`, docs/ui/compare/U.12b).
///
/// Routes: `RoutePath.kAbout` ([AboutView]) and `RoutePath.kVersionHistory`
/// (the version feature's [VersionPage], which holds the history next to
/// the update check it shares the release files and the download with).
class AboutPage extends StatelessWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  Widget build(BuildContext context) => switch (route.path) {
    RoutePath.kVersionHistory => VersionPage(route: route),
    _ => const AboutView(),
  };
}

/// The app's logo, name and version, then "关于" (online update, version
/// history, licences) and "项目" (the project page, the statement), at most
/// 720 wide (3.x `AboutPage`).
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
    final colors = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    final short = MediaQuery.sizeOf(context).height < 480;
    return Scaffold(
      // 3.x: only "back", no title.
      appBar: AppBar(toolbarHeight: short ? 48 : null),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final logoSize = constraints.maxWidth < 600 ? 80.0 : 96.0;
          return ListView(
            key: const ValueKey('about-scroll'),
            physics: const PureLiveScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              for (final child in [
                // c5: shown at once (3.x bounced it in for a second).
                Center(
                  child: Container(
                    key: const ValueKey('about-logo'),
                    width: logoSize,
                    height: logoSize,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: colors.primary.withValues(alpha: 0.08)),
                      boxShadow: [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: 0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Image.asset('assets/icons/icon.png', fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  i18n('app_name'),
                  textAlign: TextAlign.center,
                  style: styles.t18.copyWith(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                ),
                const SizedBox(height: 6),
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHigh,
                      borderRadius: const BorderRadius.all(Radius.circular(12)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      child: Text(
                        'v$appVersion',
                        key: const ValueKey('about-version'),
                        style: styles.t12.copyWith(color: colors.onSurfaceVariant, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SettingsGroup(
                  title: i18n('about'),
                  children: [
                    ValueListenableBuilder<UpdateInfo?>(
                      valueListenable: foundUpdate,
                      builder: (context, update, _) => SettingsLinkRow(
                        key: const ValueKey('about-online-update'),
                        icon: AppIcons.onlineUpdate,
                        title: i18n('online_update'),
                        subtitle: i18n('about_update_subtitle'),
                        // c3: the newer version the start-up check found;
                        // nothing otherwise (the version is shown above).
                        valueWidget: update == null || !update.isNewer ? null : _NewVersionBadge(update.version),
                        onTap: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kVersionPage)),
                      ),
                    ),
                    SettingsLinkRow(
                      key: const ValueKey('about-version-history'),
                      icon: AppIcons.versionHistory,
                      title: i18n('version_history'),
                      subtitle: i18n('history_desc'),
                      onTap: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kVersionHistory)),
                    ),
                    SettingsLinkRow(
                      key: const ValueKey('about-licenses'),
                      icon: AppIcons.licenses,
                      title: i18n('license'),
                      onTap: _openLicenses,
                    ),
                  ],
                ),
                SettingsGroup(
                  title: i18n('project'),
                  children: [
                    SettingsRow(
                      key: const ValueKey('about-project-page'),
                      icon: AppIcons.projectPage,
                      title: i18n('project_page'),
                      subtitle: projectUrl.toString(),
                      trailing: Icon(AppIcons.openExternal, size: 22, color: colors.onSurfaceVariant),
                      stackTrailing: false,
                      onTap: () => unawaited(_openProject()),
                    ),
                    // c4: v4's statement (no Firebase), an information icon
                    // and body text (3.x: a red error icon, faint text).
                    SettingsRow(
                      key: const ValueKey('about-statement'),
                      leading: Icon(AppIcons.infoLine, size: 22, color: colors.onSurfaceVariant),
                      title: i18n('project_alert'),
                      below: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          i18n('about_legalese'),
                          style: styles.t13.copyWith(color: colors.onSurface, height: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ])
                ReadableContent(
                  child: SizedBox(width: double.infinity, child: child),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// "新版本 v…" at the end of "在线更新".
class _NewVersionBadge extends StatelessWidget {
  const new(this.version);

  final String version;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const ValueKey('about-new-version'),
      decoration: BoxDecoration(color: colors.primary, borderRadius: const BorderRadius.all(Radius.circular(16))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          i18n('about_new_version', args: {'version': version}),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textStyles.t13.copyWith(color: colors.onPrimary, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
