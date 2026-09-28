import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/features/accounts/account_services.dart';
import 'package:pure_live_app/features/accounts/account_status.dart';
import 'package:pure_live_app/features/accounts/platform_account_page.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Platform accounts (principles §4.4 "平台与账号", F-ACC-01): every platform
/// with an account, what its stored login is worth, and the way to its page.
/// Cookies are encrypted with the device key and are not part of backups
/// unless the user adds a passphrase (store.md §4, §7.3).
class AccountsPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends ConsumerState<AccountsPage> {
  @override
  void initState() {
    super.initState();
    // Names come from the platforms: check each stored cookie that has a
    // user-info endpoint once per run.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = ref.read(accountStoreProvider);
      for (final platform in ref.read(enabledPlatformsProvider).where(platformHasAccount)) {
        if (store.cookie(platform) == null || ref.read(accountVerifierProvider(platform)) == null) continue;
        if (ref.read(accountCheckProvider(platform)) is! AccountUnchecked) continue;
        unawaited(ref.read(accountCheckProvider(platform).notifier).verify());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(accountRevisionProvider);
    final store = ref.watch(accountStoreProvider);
    final platforms = ref.watch(enabledPlatformsProvider).where(platformHasAccount);
    final now = DateTime.now();
    return Scaffold(
      appBar: PageAppBar(maxContentWidth: Sizes.readingWidth, title: Text(t.app.accounts)),
      body: PageBody(
        maxContentWidth: Sizes.readingWidth,
        child: ListView(
          children: [
            Padding(padding: const EdgeInsets.all(Space.s4), child: Text(t.accounts.storageNote)),
            for (final platform in platforms)
              ListTile(
                leading: PlatformLogo(platformId: platform, size: Sizes.logoLarge),
                title: Text(platformNames[platform] ?? platform),
                subtitle: Text(accountSummary(platform, store, ref.watch(accountCheckProvider(platform)), now: now)),
                trailing: const LiveIcon(LiveIcons.subpage),
                onTap: () => context.push(accountLocation(platform)),
              ),
          ],
        ),
      ),
    );
  }
}
