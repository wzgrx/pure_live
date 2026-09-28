import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/version.dart';
import 'package:pure_live_app/features/about/licenses.dart';
import 'package:pure_live_app/features/about/update_state.dart';
import 'package:pure_live_app/i18n/strings.g.dart';
import 'package:url_launcher/url_launcher.dart';

/// 关于 (F-UPD-03, principles §4.4): version and updates, project links,
/// licences (generated), privacy and trademark notes.
class AboutPage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final latest = ref.watch(updateProvider)?.latest;
    final checker = ref.watch(updateCheckerProvider);
    Future<void> open(Uri url) async {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication) && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.common.couldNotOpenLink)));
      }
    }

    return Scaffold(
      appBar: PageAppBar(maxContentWidth: Sizes.readingWidth, title: Text(t.app.about)),
      body: PageBody(
        maxContentWidth: Sizes.readingWidth,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(Space.s6),
              child: Column(
                children: [
                  Text(t.app.name, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: Space.s1),
                  Text('Pure Live · ${t.app.version} $appVersion', style: theme.textTheme.bodyMedium),
                  if (currentVersion.isPreRelease) ...[
                    const SizedBox(height: Space.s2),
                    Text(t.app.previewNotice, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.system_update_outlined),
              title: Text(t.about.versionAndUpdates),
              subtitle: Text(latest == null ? t.about.versionSubtitle : t.about.newVersion(version: latest.version)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(updateLocation),
            ),
            ListTile(
              leading: const Icon(Icons.monitor_heart_outlined),
              title: Text(t.about.platformStatus),
              subtitle: Text(t.about.platformStatusSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/me/about/status'),
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: Text(t.about.projectPage),
              subtitle: Text(checker.projectUrl.toString()),
              onTap: () => open(checker.projectUrl),
            ),
            ListTile(
              leading: const Icon(Icons.feedback_outlined),
              title: Text(t.about.feedback),
              subtitle: Text(t.about.feedbackSubtitle),
              onTap: () => open(checker.projectUrl.replace(path: '${checker.projectUrl.path}/issues')),
            ),
            ListTile(
              leading: const Icon(Icons.history_edu_outlined),
              title: Text(t.about.releases),
              onTap: () => open(checker.releasesUrl),
            ),
            ListTile(
              leading: const Icon(Icons.gavel_outlined),
              title: Text(t.about.licenses),
              subtitle: Text(t.about.licensesSubtitle),
              onTap: () {
                registerAppLicenses();
                showLicensePage(
                  context: context,
                  applicationName: t.app.name,
                  applicationVersion: appVersion,
                  applicationLegalese: 'GNU AGPL-3.0-or-later',
                );
              },
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(Space.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.about.privacy, style: theme.textTheme.titleSmall),
                  const SizedBox(height: Space.s1),
                  Text(t.about.privacyBody, style: theme.textTheme.bodySmall),
                  const SizedBox(height: Space.s3),
                  Text(t.about.trademarks, style: theme.textTheme.titleSmall),
                  const SizedBox(height: Space.s1),
                  Text(t.about.trademarksBody, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
