import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/accounts/douyu_keeper.dart';

import 'account_fakes.dart';

void main() {
  final now = DateTime(2026, 9, 28, 12);
  var calls = 0;
  Future<String?> renew({required String cookie, required String ltp0, required String did}) async {
    calls++;
    return 'dy_did=$did; dy_auth=fresh';
  }

  setUp(() => calls = 0);

  test('§8.2: a login with less than a day left is renewed with LTP0 and the device id', () async {
    final (store, secrets, settings) = await memoryAccounts({
      SecretRefs.cookie('douyu'): 'dy_did=d; dy_auth=w',
      SecretRefs.douyuLtp0: 'l',
    });
    // Saved six and a half days ago: the web cookie lasts seven.
    settings.douyuSavedAt = now.subtract(const Duration(days: 6, hours: 12));
    expect(await renewDouyuIfDue(store, renew, now: now), isTrue);
    expect(calls, 1);
    expect(store.cookie('douyu'), 'dy_did=d; dy_auth=fresh');
    expect(settings.douyuSavedAt, now);
    // Fresh now: nothing to do.
    expect(await renewDouyuIfDue(store, renew, now: now.add(const Duration(hours: 6))), isFalse);
    expect(calls, 1);
  });

  test('no renewal without the keys, without a login or with time left', () async {
    final (fresh, _, freshSettings) = await memoryAccounts({
      SecretRefs.cookie('douyu'): 'dy_did=d; dy_auth=w',
      SecretRefs.douyuLtp0: 'l',
    });
    freshSettings.douyuSavedAt = now.subtract(const Duration(days: 2));
    expect(await renewDouyuIfDue(fresh, renew, now: now), isFalse);

    final (noKeys, _, noKeysSettings) = await memoryAccounts({SecretRefs.cookie('douyu'): 'dy_auth=w'});
    noKeysSettings.douyuSavedAt = now.subtract(const Duration(days: 8));
    expect(await renewDouyuIfDue(noKeys, renew, now: now), isFalse);

    final (guest, _, _) = await memoryAccounts({SecretRefs.cookie('douyu'): 'dy_did=d', SecretRefs.douyuLtp0: 'l'});
    expect(await renewDouyuIfDue(guest, renew, now: now), isFalse);
    expect(calls, 0);
  });
}
