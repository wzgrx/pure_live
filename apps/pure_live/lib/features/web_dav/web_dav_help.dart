import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// How to set up a WebDAV server, with Jianguoyun as the example (3.x
/// `WebDavHelpPage`): 3.x's steps, each with its screenshot (tap to view it
/// full screen and zoom).
class WebDavHelpPage extends StatelessWidget {
  /// Creates the page.
  const new({super.key});

  static final Uri _officialHelp = Uri.parse('https://help.jianguoyun.com/?p=2064');

  /// Jianguoyun's WebDAV address.
  static const String davUrl = 'https://dav.jianguoyun.com/dav/';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The settings groups' look (U.11b c13): 13 px primary titles, cards
    // on the low container with 16 px corners.
    Widget section(String key) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        i18n(key),
        style: context.textStyles.t13.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
      ),
    );
    Widget card(List<Widget> children) => Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      ),
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
      appBar: settingsPageAppBar(context, title: i18n('webdav_help_title')),
      body: ReadableContent(
        child: ListView(
          physics: const PureLiveScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
          children: [
            section('webdav_help_intro_section'),
            card([body('webdav_help_intro_body')]),
            section('webdav_help_params_section'),
            card([
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(AppIcons.link, color: theme.colorScheme.primary),
                title: Text(i18n('webdav_help_server_title')),
                subtitle: SelectableText(davUrl, style: TextStyle(color: theme.colorScheme.primary)),
                trailing: IconButton(
                  tooltip: i18n('webdav_help_copy_server'),
                  icon: const Icon(AppIcons.copyValue, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(const ClipboardData(text: davUrl));
                    AppNavigator.toast(i18n('copied_to_clipboard'));
                  },
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(AppIcons.mail, color: theme.colorScheme.primary),
                title: Text(i18n('webdav_help_username_title')),
                subtitle: Text(i18n('webdav_help_username_hint')),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(AppIcons.password, color: theme.colorScheme.primary),
                title: Text(i18n('webdav_help_app_password_title')),
                subtitle: Text(i18n('webdav_help_app_password_hint')),
              ),
            ]),
            section('webdav_help_register_section'),
            card([
              body('webdav_help_register_steps'),
              const WebDavScreenshot(index: 1),
              const SizedBox(height: 12),
              body('webdav_help_register_form'),
              const WebDavScreenshot(index: 2),
            ]),
            section('webdav_help_login_section'),
            card([body('webdav_help_login_steps'), const WebDavScreenshot(index: 3)]),
            section('webdav_help_password_section'),
            card([
              body('webdav_help_account_steps'),
              const WebDavScreenshot(index: 4),
              const SizedBox(height: 12),
              body('webdav_help_security_steps'),
              const WebDavScreenshot(index: 5),
              const SizedBox(height: 12),
              body('webdav_help_generate_steps'),
              const WebDavScreenshot(index: 6),
              const SizedBox(height: 12),
              body('webdav_help_password_once'),
              const WebDavScreenshot(index: 7),
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

/// One of the help page's screenshots (3.x's seven, in its order): a
/// preview at most 240 high; a tap opens it full screen, zoomable.
class WebDavScreenshot extends StatelessWidget {
  /// Creates screenshot [index] (1..7).
  const new({required this.index, super.key});

  /// The screenshot's number.
  final int index;

  /// The assets in the order of the steps (3.x `imgUrls`).
  static const List<String> assets = [
    'assets/webdav/00_home.png',
    'assets/webdav/02_register.png',
    'assets/webdav/03_login.png',
    'assets/webdav/01_avatar_menu.png',
    'assets/webdav/04_security.png',
    'assets/webdav/05_add_app.png',
    'assets/webdav/06_get_pwd.png',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = i18n('webdav_help_screenshot_label', args: {'number': '$index'});
    final asset = assets[index - 1];
    Widget failed(BuildContext context, Object error, StackTrace? stack) => Container(
      height: 48,
      alignment: Alignment.center,
      child: Text(i18n('webdav_help_image_failed'), style: context.textStyles.t11.copyWith(color: theme.hintColor)),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          key: ValueKey('webdav-help-image-$index'),
          borderRadius: BorderRadius.circular(10),
          onTap: () => unawaited(
            showAppDialog<void>(
              context: context,
              builder: (dialogContext) => Dialog.fullscreen(
                backgroundColor: OnVideoColors.ground,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: InteractiveViewer(
                        maxScale: 5,
                        child: Center(
                          child: Image.asset(asset, semanticLabel: label, errorBuilder: failed),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: SafeArea(
                        child: IconButton.filledTonal(
                          key: const ValueKey('webdav-help-image-close'),
                          tooltip: i18n('close'),
                          icon: const Icon(AppIcons.close),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: Image.asset(
                asset,
                width: double.infinity,
                fit: BoxFit.contain,
                semanticLabel: label,
                errorBuilder: failed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
