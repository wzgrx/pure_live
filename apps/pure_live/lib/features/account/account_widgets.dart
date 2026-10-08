import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/account/account_state.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// The colour of [tone] (docs/A-界面设计/A12-账号和数据界面/A12.1-账号总览 c2): fine in the primary
/// colour, a warning in yellow, a failure in red, nothing stored or a check
/// on its way in the quiet text colour.
Color accountToneColor(ThemeData theme, AccountTone tone) => switch (tone) {
  AccountTone.idle || AccountTone.busy => theme.colorScheme.onSurfaceVariant,
  AccountTone.ok => theme.colorScheme.primary,
  AccountTone.warning => LiveSemanticColors.warning(theme.colorScheme.brightness),
  AccountTone.error => theme.colorScheme.error,
};

/// The state of one platform's login at the top of its page
/// (docs/A-界面设计/A12-账号和数据界面/A12.2-登录和Cookie): the logo, the name and the same sentence as the
/// accounts list, with an optional action ("重新核验").
class AccountStatusCard extends StatelessWidget {
  /// Creates the card.
  const new({required this.platformId, required this.name, required this.status, this.action, super.key});

  /// The platform (its logo).
  final String platformId;

  /// The platform's name.
  final String name;

  /// What to say.
  final AccountStatus status;

  /// A button after the sentence.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('account-status'),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          PlatformLogo(platformId, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: context.textStyles.t15.emphasis),
                const SizedBox(height: 2),
                Text(
                  status.text,
                  key: const ValueKey('account-status-text'),
                  style: context.textStyles.t13.copyWith(color: accountToneColor(theme, status.tone), height: 1.45),
                ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// A warning above the list or a page (the cookies this device cannot
/// read, the missing in-app browser).
class AccountNotice extends StatelessWidget {
  /// Creates the notice.
  const new({required this.text, super.key});

  /// What to say.
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final warning = LiveSemanticColors.warning(scheme.brightness);
    return Container(
      key: const ValueKey('account-notice'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.info, size: 20, color: warning),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: context.textStyles.t13.copyWith(height: 1.5))),
        ],
      ),
    );
  }
}

/// The instructions banner (3.x `_buildTipBanner`), with a link that opens
/// the platform's website (docs/A-界面设计/A12-账号和数据界面/A12.2-登录和Cookie c4).
class AccountTipBanner extends StatelessWidget {
  /// Creates the banner.
  const new({this.text, this.body, this.website, this.websiteLabel, super.key});

  /// The instructions.
  final String? text;

  /// Richer instructions instead of [text].
  final Widget? body;

  /// Where the user signs in.
  final Uri? website;

  /// The link's text.
  final String? websiteLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final site = website;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(AppIcons.info, size: 18, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                body ?? Text(text ?? '', style: accountTipStyle(context)),
                if (site != null)
                  TextButton.icon(
                    key: const ValueKey('account-open-website'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                      textStyle: context.textStyles.t13,
                    ),
                    onPressed: () => openAccountWebsite(site),
                    icon: const Icon(AppIcons.openExternal, size: 16),
                    label: Text(websiteLabel ?? site.host),
                  )
                else
                  const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The style of instruction text.
TextStyle accountTipStyle(BuildContext context) =>
    context.textStyles.t13.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.45);

/// Opens [uri] in the browser; says so when no browser opens it.
Future<void> openAccountWebsite(Uri uri) async {
  try {
    if (!await AppNavigator.openExternal(uri)) AppNavigator.toast(i18n('external_browser_not_opened'));
  } on Object {
    AppNavigator.toast(i18n('external_browser_not_opened'));
  }
}

/// Asks before [action]; [destructive] paints the button in the error
/// colour.
Future<bool> confirmAccountAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  String? cancel,
  bool destructive = true,
}) async {
  final confirmed = await showAppConfirmDialog(
    context: context,
    title: title,
    message: message,
    confirmLabel: action,
    cancelLabel: cancel,
    danger: destructive,
    cancelKey: const ValueKey('account-confirm-cancel'),
    confirmKey: const ValueKey('account-confirm-ok'),
  );
  return confirmed;
}

/// The sign-out question for [name], the list's and a platform page's alike
/// (3.x `account_page.dart:244`, words unchanged; UI_PLAN 3.7: one action,
/// one dialog, one set of words).
Future<bool> confirmSignOut(BuildContext context, String name) => confirmAccountAction(
  context,
  title: i18n('logout'),
  message: i18n('confirm_logout_named', args: {'name': name}),
  action: i18n('logout'),
);
