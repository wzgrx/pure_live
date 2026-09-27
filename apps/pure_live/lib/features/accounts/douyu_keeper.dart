import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live_app/features/accounts/account_services.dart';
import 'package:pure_live_app/features/diagnostics/diagnostics_page.dart';

/// Renews the stored Douyu login when less than a day is left (spec/sites/
/// douyu.md §8.2), quietly: [now] is the moment; true when it renewed. A
/// login without a session token or without LTP0 and the device id is left
/// alone; a failed renewal keeps the old login.
Future<bool> renewDouyuIfDue(AccountStore store, DouyuRenewer renew, {required DateTime now}) async {
  final cookie = store.cookie('douyu');
  if (cookie == null || DouyuSession.sessionToken(cookie) == null) return false;
  if (!DouyuSession.shouldRenew(cookie, now: now, savedAt: store.douyuSavedAt)) return false;
  final keys = DouyuSession.credentials(cookie, storedLtp0: store.douyuLtp0, storedDid: store.douyuDid);
  final ltp0 = keys.ltp0;
  final did = keys.did;
  if (ltp0 == null || did == null) return false;
  final renewed = await renew(cookie: cookie, ltp0: ltp0, did: did);
  if (renewed == null) return false;
  await store.saveDouyu(cookie: renewed, savedAt: now);
  return true;
}

/// Keeps the Douyu login fresh (§8.2): at start and every six hours, so
/// plays never meet an expired session; `PureLiveApp` watches it.
final Provider<void> douyuSessionKeeperProvider = Provider<void>((ref) {
  Future<void> check() async {
    try {
      if (await renewDouyuIfDue(ref.read(accountStoreProvider), ref.read(douyuRenewerProvider), now: DateTime.now())) {
        ref.read(appLogProvider).info('accounts', 'douyu session renewed');
      }
    } on Object catch (error) {
      // Never the cookie: only the kind of failure.
      ref.read(appLogProvider).warning('accounts', 'douyu session renewal failed', error.runtimeType);
    }
  }

  unawaited(check());
  final timer = Timer.periodic(const Duration(hours: 6), (_) => unawaited(check()));
  ref.onDispose(timer.cancel);
});
