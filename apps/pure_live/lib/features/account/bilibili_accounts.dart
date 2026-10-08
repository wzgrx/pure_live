import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The name a remembered sign-in shows: its account name, or its uid when
/// the name is not known.
String savedAccountName(SavedAccount account) =>
    account.name.isEmpty ? i18n('account_uid', args: {'uid': '${account.uid}'}) : account.name;

/// "已记住的账号" on Bilibili's page (docs/K-账号和登录/K01-账号和登录方式/K01.2-哔哩哔哩多账号, V01.2
/// S6): every remembered sign-in with its letter, name and uid, the
/// current one marked, the others with "切换" and a delete button; the last
/// row adds an account (the QR login). The current one has no buttons: it
/// is signed out with the page's "退出登录".
class BilibiliAccountsGroup extends StatelessWidget {
  /// Creates the group.
  const new({
    required this.accounts,
    required this.isCurrent,
    required this.onSwitch,
    required this.onForget,
    required this.onAdd,
    this.busy = false,
    super.key,
  });

  /// The remembered sign-ins, most recently used first.
  final List<SavedAccount> accounts;

  /// Whether a sign-in is the current one.
  final bool Function(SavedAccount account) isCurrent;

  /// Switches to a sign-in (asks first).
  final void Function(SavedAccount account) onSwitch;

  /// Forgets a sign-in (asks first).
  final void Function(SavedAccount account) onForget;

  /// Opens the QR login for another account.
  final VoidCallback onAdd;

  /// A switch or a delete is running: the buttons wait.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final full = accounts.length >= AccountRoster.limit;
    return SettingsGroup(
      key: const ValueKey('bilibili-accounts'),
      title: i18n('account_saved_accounts'),
      footer: i18n('account_saved_accounts_note', args: {'count': '${AccountRoster.limit}'}),
      children: [
        for (final account in accounts) _row(context, account, current: isCurrent(account)),
        ListTile(
          key: const ValueKey('bilibili-account-add'),
          enabled: !busy,
          minTileHeight: 64,
          horizontalTitleGap: 16,
          contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          leading: SizedBox.square(
            dimension: 36,
            child: DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primary.withValues(alpha: 0.1)),
              child: Icon(AppIcons.add, size: 20, color: scheme.primary),
            ),
          ),
          title: Text(i18n('account_add'), style: context.textStyles.t15.regular),
          subtitle: Text(
            full ? i18n('account_add_full', args: {'count': '${AccountRoster.limit}'}) : i18n('account_add_hint'),
            style: context.textStyles.t12.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
          ),
          onTap: onAdd,
        ),
      ],
    );
  }

  Widget _row(BuildContext context, SavedAccount account, {required bool current}) {
    final scheme = Theme.of(context).colorScheme;
    final name = savedAccountName(account);
    final uid = i18n('account_uid', args: {'uid': '${account.uid}'});
    final key = 'bilibili-account-${account.uid}';
    return ListTile(
      key: ValueKey(key),
      minTileHeight: 64,
      horizontalTitleGap: 16,
      contentPadding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
      leading: CommonAvatar(avatarUrl: null, fallbackName: account.name.isEmpty ? null : account.name, radius: 18),
      title: Text(name, style: context.textStyles.t15.regular),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          current ? '$uid · ${i18n('account_current')}' : uid,
          key: ValueKey('$key-state'),
          style: context.textStyles.t12.copyWith(
            color: current ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: current ? FontWeight.w600 : FontWeight.w400,
            height: 1.4,
          ),
        ),
      ),
      trailing: current
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  key: ValueKey('$key-switch'),
                  onPressed: busy ? null : () => onSwitch(account),
                  child: Text(i18n('account_switch')),
                ),
                IconButton(
                  key: ValueKey('$key-forget'),
                  tooltip: i18n('account_forget'),
                  onPressed: busy ? null : () => onForget(account),
                  icon: Icon(AppIcons.delete, size: 18, color: scheme.error.withValues(alpha: 0.8)),
                ),
              ],
            ),
      onTap: current || busy ? null : () => onSwitch(account),
    );
  }
}
