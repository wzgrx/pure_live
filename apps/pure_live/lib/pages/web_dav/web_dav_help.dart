import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// How to set up a WebDAV server, with Jianguoyun as the example (3.x
/// `WebDavHelpPage`). The steps are 3.x's; its screenshots are not in the
/// app's assets yet (docs/modules/M13.10-backup.md).
class WebDavHelpPage extends StatelessWidget {
  /// Creates the page.
  const new({super.key});

  static final Uri _officialHelp = Uri.parse('https://help.jianguoyun.com/?p=2064');

  /// Jianguoyun's WebDAV address.
  static const String davUrl = 'https://dav.jianguoyun.com/dav/';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String key) => Padding(
      padding: const EdgeInsets.only(left: 4, top: 22, bottom: 10),
      child: Text(i18n(key), style: context.textStyles.t16SemiBold),
    );
    Widget card(List<Widget> children) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
    Widget body(String key) => Text(i18n(key), style: context.textStyles.t13.copyWith(height: 1.6));
    const issues = [
      ('webdav_help_issue_credentials_q', 'webdav_help_issue_credentials_a'),
      ('webdav_help_issue_browser_q', 'webdav_help_issue_browser_a'),
      ('webdav_help_issue_upload_q', 'webdav_help_issue_upload_a'),
      ('webdav_help_issue_timeout_q', 'webdav_help_issue_timeout_a'),
      ('webdav_help_issue_revoke_q', 'webdav_help_issue_revoke_a'),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(i18n('webdav_help_title'))),
      body: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          section('webdav_help_intro_section'),
          card([body('webdav_help_intro_body')]),
          section('webdav_help_params_section'),
          card([
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Remix.links_line, color: theme.colorScheme.primary),
              title: Text(i18n('webdav_help_server_title')),
              subtitle: SelectableText(davUrl, style: TextStyle(color: theme.colorScheme.primary)),
              trailing: IconButton(
                tooltip: i18n('webdav_help_copy_server'),
                icon: const Icon(Remix.file_copy_line, size: 18),
                onPressed: () async {
                  await Clipboard.setData(const ClipboardData(text: davUrl));
                  AppNavigator.toast(i18n('copied_to_clipboard'));
                },
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Remix.mail_line, color: theme.colorScheme.primary),
              title: Text(i18n('webdav_help_username_title')),
              subtitle: Text(i18n('webdav_help_username_hint')),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Remix.lock_password_line, color: theme.colorScheme.primary),
              title: Text(i18n('webdav_help_app_password_title')),
              subtitle: Text(i18n('webdav_help_app_password_hint')),
            ),
          ]),
          section('webdav_help_register_section'),
          card([body('webdav_help_register_steps'), const SizedBox(height: 8), body('webdav_help_register_form')]),
          section('webdav_help_login_section'),
          card([body('webdav_help_login_steps')]),
          section('webdav_help_password_section'),
          card([
            body('webdav_help_account_steps'),
            body('webdav_help_security_steps'),
            body('webdav_help_generate_steps'),
            body('webdav_help_password_once'),
          ]),
          section('webdav_help_generic_section'),
          card([body('webdav_help_generic_body')]),
          section('webdav_help_issues_section'),
          card([
            for (final (question, answer) in issues) ...[
              Text(i18n(question), style: context.textStyles.t13SemiBold.copyWith(color: theme.colorScheme.primary)),
              const SizedBox(height: 4),
              Text(i18n(answer), style: context.textStyles.t12Muted.copyWith(height: 1.5)),
              const SizedBox(height: 10),
            ],
          ]),
          section('webdav_help_limits_section'),
          card([body('webdav_help_limits_body')]),
          section('webdav_help_summary_section'),
          card([body('webdav_help_summary_body')]),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => unawaited(_openOfficialHelp()),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(i18n('webdav_help_open_official')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openOfficialHelp() async {
    var opened = false;
    try {
      opened = await AppNavigator.openExternal(_officialHelp);
    } on Object {
      opened = false;
    }
    if (!opened) AppNavigator.toast(i18n('external_browser_not_opened'));
  }
}
