import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/account/account_state.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// The colour of [tone].
Color accountToneColor(ThemeData theme, AccountTone tone) => switch (tone) {
  AccountTone.idle => theme.hintColor.withValues(alpha: 0.75),
  AccountTone.ok || AccountTone.busy => theme.colorScheme.primary,
  AccountTone.warning => Colors.orange.shade800,
  AccountTone.error => theme.colorScheme.error,
};

/// The icon of [tone].
IconData accountToneIcon(AccountTone tone) => switch (tone) {
  AccountTone.idle => Remix.user_line,
  AccountTone.ok => Remix.checkbox_circle_line,
  AccountTone.busy => Remix.loader_4_line,
  AccountTone.warning => Remix.error_warning_line,
  AccountTone.error => Remix.close_circle_line,
};

/// The current state of a login above its editor: icon, sentence, and an
/// optional action (re-check).
class AccountStatusCard extends StatelessWidget {
  /// Creates the card.
  const new({required this.status, this.action, super.key});

  /// What to say.
  final AccountStatus status;

  /// A button after the sentence.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accountToneColor(theme, status.tone);
    return Container(
      key: const ValueKey('account-status'),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          if (status.tone == AccountTone.busy)
            SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: color))
          else
            Icon(accountToneIcon(status.tone), size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              status.text,
              style: context.textStyles.t13.copyWith(color: color, fontWeight: FontWeight.w600, height: 1.35),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// The instructions banner (3.x `_buildTipBanner`), with a button that
/// opens the platform's website.
class AccountTipBanner extends StatelessWidget {
  /// Creates the banner.
  const new({this.text, this.body, this.website, this.websiteLabel, super.key});

  /// The instructions.
  final String? text;

  /// Richer instructions instead of [text].
  final Widget? body;

  /// Where the user signs in.
  final Uri? website;

  /// The website button's text.
  final String? websiteLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final site = website;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Remix.information_line, size: 18, color: theme.colorScheme.primary.withValues(alpha: 0.8)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                body ?? Text(text ?? '', style: accountTipStyle(context)),
                if (site != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: TextButton.icon(
                      key: const ValueKey('account-open-website'),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                      onPressed: () => openAccountWebsite(site),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: Text(websiteLabel ?? site.host),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The style of instruction text.
TextStyle accountTipStyle(BuildContext context) {
  final theme = Theme.of(context);
  return context.textStyles.t13.copyWith(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8), height: 1.4);
}

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
  bool destructive = true,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final colors = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        title: Text(title),
        content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(message)),
        actionsOverflowDirection: VerticalDirection.down,
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            key: const ValueKey('account-confirm-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(i18n('cancel')),
          ),
          FilledButton(
            key: const ValueKey('account-confirm-ok'),
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.onError)
                : null,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(action),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

/// The sign-out question for [name] (3.x `confirm_logout_named`).
Future<bool> confirmSignOut(BuildContext context, String name) => confirmAccountAction(
  context,
  title: i18n('logout'),
  message: i18n('confirm_logout_named', args: {'name': name}),
  action: i18n('logout'),
);
