import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/accounts/account_services.dart';
import 'package:pure_live_app/features/accounts/account_status.dart';
import 'package:pure_live_app/features/accounts/douyu_account.dart';

import 'account_fakes.dart';

String _jwt(DateTime exp) =>
    'h.${base64Url.encode(utf8.encode(jsonEncode({'exp': exp.millisecondsSinceEpoch ~/ 1000}))).replaceAll('=', '')}.s';

void main() {
  final now = DateTime(2026, 9, 28, 12);

  group('F-ACC-01 summary', () {
    test('never shows the cookie; B 站 shows the uid of the same cookie before a check', () async {
      final (store, _, _) = await memoryAccounts({
        SecretRefs.cookie('bilibili'): 'SESSDATA=secret; DedeUserID=42',
        SecretRefs.cookie('huya'): 'yyuid=1; udb_passport=secret',
      });
      expect(accountSummary('bilibili', store, const AccountUnchecked(), now: now), '已登录 · UID 42');
      expect(
        accountSummary(
          'bilibili',
          store,
          const AccountVerified(AccountIdentity(name: '小明', uid: '42')),
          now: now,
        ),
        '已登录 · 小明（UID 42）',
      );
      expect(accountSummary('bilibili', store, const AccountCheckFailed('网络连接失败'), now: now), '已登录 · 校验失败：网络连接失败');
      expect(accountSummary('huya', store, const AccountUnchecked(), now: now), '已填 Cookie');
      expect(accountSummary('douyin', store, const AccountUnchecked(), now: now), '未登录');
      expect(accountSummary('douyin', store, const AccountExpired(), now: now), '登录已失效，请重新登录');
      for (final check in [const AccountUnchecked(), const AccountChecking(), const AccountExpired()]) {
        expect(accountSummary('huya', store, check, now: now), isNot(contains('secret')));
      }
    });

    test('Douyu shows the session state and its end (spec/sites/douyu.md §8.1)', () async {
      final (store, secrets, settings) = await memoryAccounts({SecretRefs.cookie('douyu'): 'dy_did=d; dy_auth=w'});
      expect(accountSummary('douyu', store, const AccountUnchecked(), now: now), '已登录 · 有效期未知');
      settings.douyuSavedAt = now.subtract(const Duration(days: 2));
      expect(
        accountSummary('douyu', store, const AccountUnchecked(), now: now),
        '已登录 · 有效期到 ${formatAccountTime(now.add(const Duration(days: 5)))}',
      );
      await secrets.write(SecretRefs.douyuLtp0, 'l');
      expect(accountSummary('douyu', store, const AccountUnchecked(), now: now), endsWith('，到期前可续期'));
      settings.douyuSavedAt = now.subtract(const Duration(days: 8));
      expect(accountSummary('douyu', store, const AccountUnchecked(), now: now), startsWith('已在'));
      await secrets.write(SecretRefs.douyuLtp0, null);
      await secrets.write(SecretRefs.cookie('douyu'), 'dy_auth=w');
      expect(accountSummary('douyu', store, const AccountUnchecked(), now: now), '已过期，请重新登录');
      await secrets.write(SecretRefs.cookie('douyu'), 'dy_did=d');
      expect(accountSummary('douyu', store, const AccountUnchecked(), now: now), '已填 Cookie，但里面没有登录信息');
    });
  });

  group('F-ACC-01 校验', () {
    Future<(ProviderContainer, AccountStore, MemoryAccountSettings)> container(
      Map<String, String> secrets,
      AccountVerifier verifier,
    ) async {
      final (store, _, settings) = await memoryAccounts(secrets);
      final container = ProviderContainer(
        overrides: [
          accountStoreProvider.overrideWithValue(store),
          accountSettingsProvider.overrideWithValue(settings),
          accountVerifierProvider.overrideWith((ref, platform) => verifier),
        ],
      );
      addTearDown(container.dispose);
      return (container, store, settings);
    }

    test('a verified B 站 account records its uid', () async {
      final (c, _, settings) = await container({
        SecretRefs.cookie('bilibili'): 'SESSDATA=s',
      }, () async => const AccountIdentity(name: '小明', uid: '7'));
      await c.read(accountCheckProvider('bilibili').notifier).verify();
      expect(c.read(accountCheckProvider('bilibili')), isA<AccountVerified>());
      expect(settings.bilibiliUid, 7);
    });

    test('B 站 NeedsLogin clears the stored cookie and says so (spec/sites/bilibili.md §8.2)', () async {
      final (c, store, _) = await container({
        SecretRefs.cookie('bilibili'): 'SESSDATA=old',
      }, () async => throw const NeedsLogin('bilibili', 'code -101'));
      c.listen(accountCheckProvider('bilibili'), (_, _) {});
      await c.read(accountCheckProvider('bilibili').notifier).verify();
      await Future<void>.delayed(Duration.zero);
      expect(store.cookie('bilibili'), isNull);
      expect(c.read(accountCheckProvider('bilibili')), isA<AccountExpired>());
    });

    test('other platforms keep the cookie on NeedsLogin; a network failure changes nothing', () async {
      Object answer = const NeedsLogin('douyin', '20003');
      final (c, store, _) = await container({
        SecretRefs.cookie('douyin'): 'sessionid=s',
      }, () async => Error.throwWithStackTrace(answer, StackTrace.current));
      await c.read(accountCheckProvider('douyin').notifier).verify();
      expect(store.cookie('douyin'), 'sessionid=s');
      expect(c.read(accountCheckProvider('douyin')), isA<AccountExpired>());
      answer = const NetworkFailure('douyin', 'offline');
      await c.read(accountCheckProvider('douyin').notifier).verify();
      expect(c.read(accountCheckProvider('douyin')), isA<AccountCheckFailed>());
    });

    test('an older check never overwrites the state of a newer cookie', () async {
      final answer = Completer<AccountIdentity>();
      final (c, store, _) = await container({SecretRefs.cookie('douyin'): 'sessionid=old'}, () => answer.future);
      c.listen(accountCheckProvider('douyin'), (_, _) {});
      final running = c.read(accountCheckProvider('douyin').notifier).verify();
      expect(c.read(accountCheckProvider('douyin')), isA<AccountChecking>());
      await store.saveCookie('douyin', 'sessionid=new');
      await Future<void>.delayed(Duration.zero);
      answer.complete(const AccountIdentity(name: '旧账号'));
      await running;
      expect(c.read(accountCheckProvider('douyin')), isA<AccountUnchecked>());
    });
  });

  group('spec/sites/douyu.md §8.4 the Douyu editor', () {
    test('a page cookie is stored with its save time and the keys it carries', () async {
      final (store, _, settings) = await memoryAccounts();
      final message = await saveDouyuInput(
        store,
        pasted: 'Cookie: dy_did=d; dy_auth=w; LTP0=l',
        typedLtp0: '',
        typedDid: '',
        now: now,
      );
      expect(store.cookie('douyu'), 'dy_did=d; dy_auth=w; LTP0=l');
      expect((store.douyuLtp0, store.douyuDid), ('l', 'd'));
      expect(settings.douyuSavedAt, now);
      expect(message, startsWith('已保存'));
    });

    test('a passport cookie stores only LTP0 and dy_did and keeps the login', () async {
      final (store, _, settings) = await memoryAccounts({SecretRefs.cookie('douyu'): 'dy_did=d; dy_auth=w'});
      final message = await saveDouyuInput(
        store,
        pasted: 'LTP0=l2; dy_did=d2; acf_stk=s; acf_ssid=x',
        typedLtp0: '',
        typedDid: '',
        now: now,
      );
      expect(store.cookie('douyu'), 'dy_did=d; dy_auth=w', reason: 'not a login; never a play cookie');
      expect((store.douyuLtp0, store.douyuDid), ('l2', 'd2'));
      expect(settings.douyuSavedAt, isNull);
      expect(message, contains('原来的登录保留'));
    });

    test('a cookie without a session never replaces a stored login; typed keys win', () async {
      final (store, _, _) = await memoryAccounts({SecretRefs.cookie('douyu'): 'dy_auth=w'});
      await saveDouyuInput(store, pasted: 'dy_did=x; LTP0=c', typedLtp0: ' typed ', typedDid: '', now: now);
      expect(store.cookie('douyu'), 'dy_auth=w');
      expect((store.douyuLtp0, store.douyuDid), ('typed', 'x'));
    });

    test('立即续期 stores the renewed cookie and its time; nothing renewed keeps the old one', () async {
      final (store, _, settings) = await memoryAccounts({
        SecretRefs.cookie('douyu'): 'dy_auth=w',
        SecretRefs.douyuLtp0: 'l',
        SecretRefs.douyuDid: 'd',
      });
      final calls = <String>[];
      final renewed = 'dy_auth=w; acf_jwt_token=${_jwt(now.add(const Duration(days: 7)))}';
      Future<String?> renew({required String cookie, required String ltp0, required String did}) async {
        calls.add('$ltp0/$did');
        return calls.length == 1 ? renewed : null;
      }

      expect(await renewDouyuNow(store, renew, now: now), startsWith('已续期，新的有效期到'));
      expect(calls, ['l/d']);
      expect(store.cookie('douyu'), renewed);
      expect(settings.douyuSavedAt, now);
      expect(await renewDouyuNow(store, renew, now: now), '斗鱼没有返回新的登录信息，续期没有生效');
      expect(store.cookie('douyu'), renewed);
    });

    test('立即续期 needs a login and both keys; failures are reported, not thrown', () async {
      final (store, secrets, _) = await memoryAccounts({SecretRefs.cookie('douyu'): 'dy_auth=w'});
      Future<String?> fail({required String cookie, required String ltp0, required String did}) async =>
          throw const NetworkFailure('douyu', 'offline');
      expect(await renewDouyuNow(store, fail, now: now), '缺少 LTP0 或 dy_did，没法续期');
      await secrets.writeAll({SecretRefs.douyuLtp0: 'l', SecretRefs.douyuDid: 'd'});
      expect(await renewDouyuNow(store, fail, now: now), '续期失败：网络连接失败');
      await secrets.write(SecretRefs.cookie('douyu'), 'dy_did=d');
      expect(await renewDouyuNow(store, fail, now: now), 'Cookie 里没有登录信息，没法续期');
    });
  });
}
