import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/features/backup/backup_flow.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Location of the first-run wizard.
const welcomeLocation = '/welcome';

/// The first-run wizard (F-NEW-08, store.md §11): the preview is a separate
/// installation that cannot read the 3.x data, so it offers the three ways
/// to bring data in (file, WebDAV, LAN) or to start empty. Shown once.
class OnboardingPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  bool _busy = false;

  void _finish() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/follows');
    }
  }

  Future<void> _importFile() async {
    setState(() => _busy = true);
    try {
      final document = await pickBackupFile();
      if (document == null || !mounted) return;
      final report = await confirmAndRestore(context, service: ref.read(backupServiceProvider), document: document);
      if (report != null && mounted) _finish();
    } on Object catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(backupErrorText(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget option(LiveIcons icon, String title, String subtitle, VoidCallback onTap) => Card(
      margin: const EdgeInsets.only(bottom: Space.s3),
      child: ListTile(
        leading: LiveIcon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const LiveIcon(LiveIcons.subpage),
        onTap: _busy ? null : onTap,
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(Space.s6),
              children: [
                if (_busy) const LinearProgressIndicator(),
                const SizedBox(height: Space.s6),
                Text(t.onboarding.welcome(app: t.app.name), style: theme.textTheme.headlineSmall),
                const SizedBox(height: Space.s3),
                Text(t.onboarding.intro),
                const SizedBox(height: Space.s6),
                option(LiveIcons.importFile, t.onboarding.fromFile, t.onboarding.fromFileSubtitle, _importFile),
                option(
                  LiveIcons.cloud,
                  t.onboarding.fromWebdav,
                  t.onboarding.fromWebdavSubtitle,
                  () => context.go('/me/backup/webdav'),
                ),
                option(
                  LiveIcons.lanSync,
                  t.onboarding.fromDevice,
                  t.onboarding.fromDeviceSubtitle,
                  () => context.go('/me/backup/lan?receive=1'),
                ),
                const SizedBox(height: Space.s3),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: _busy ? null : _finish, child: Text(t.onboarding.skip)),
                ),
                const SizedBox(height: Space.s3),
                Text(t.onboarding.laterHint, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
