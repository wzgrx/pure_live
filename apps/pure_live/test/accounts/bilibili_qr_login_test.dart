import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live_app/features/accounts/account_services.dart';
import 'package:pure_live_app/features/accounts/bilibili_qr_login.dart';

import 'account_fakes.dart';

void main() {
  const interval = Duration(seconds: 3);

  test('§8.3 waiting → scanned → confirmed → verified and stored', () {
    fakeAsync((async) {
      final api = FakeBilibiliLogin()
        ..answers.addAll([
          (state: BilibiliQrState.waiting, cookie: null),
          (state: BilibiliQrState.scanned, cookie: null),
          (state: BilibiliQrState.confirmed, cookie: 'SESSDATA=s; DedeUserID=42'),
        ]);
      final saved = <(String, AccountIdentity)>[];
      final login = BilibiliQrLogin(api: api, save: (cookie, id) async => saved.add((cookie, id)));
      unawaited(login.start());
      async.flushMicrotasks();
      expect(login.phase, QrLoginPhase.waiting);
      expect(login.code.toString(), contains('k1'));
      expect(api.polls, isEmpty, reason: 'the first poll waits one interval');

      async.elapse(interval);
      expect(api.polls, ['k1']);
      expect(login.phase, QrLoginPhase.waiting);
      async.elapse(interval);
      expect(login.phase, QrLoginPhase.scanned);
      async.elapse(interval);
      expect(login.phase, QrLoginPhase.done);
      expect(api.checked, ['SESSDATA=s; DedeUserID=42'], reason: 'verified before stored');
      expect(saved.single.$2, const AccountIdentity(name: '测试', uid: '42'));

      async.elapse(interval * 5);
      expect(api.polls, hasLength(3), reason: 'no poll after the end');
      login.dispose();
    });
  });

  test('§8.3 the next poll starts an interval after the previous one finished', () {
    fakeAsync((async) {
      final slow = Completer<QrPoll>();
      final api = _SlowLogin(slow);
      final login = BilibiliQrLogin(api: api, save: (_, _) async {});
      unawaited(login.start());
      async.elapse(interval);
      expect(api.polls, hasLength(1));
      async.elapse(interval * 3);
      expect(api.polls, hasLength(1), reason: 'one poll at a time');
      slow.complete((state: BilibiliQrState.waiting, cookie: null));
      async
        ..flushMicrotasks()
        ..elapse(interval - const Duration(milliseconds: 1));
      expect(api.polls, hasLength(1));
      async.elapse(const Duration(milliseconds: 1));
      expect(api.polls, hasLength(2));
      login.dispose();
    });
  });

  test('§8.3 expiry stops polling; a refresh gets a new code', () {
    fakeAsync((async) {
      final api = FakeBilibiliLogin()..answers.add((state: BilibiliQrState.expired, cookie: null));
      final login = BilibiliQrLogin(api: api, save: (_, _) async {});
      unawaited(login.start());
      async.elapse(interval);
      expect(login.phase, QrLoginPhase.expired);
      async.elapse(interval * 3);
      expect(api.polls, ['k1']);

      unawaited(login.start());
      async.elapse(interval);
      expect(login.phase, QrLoginPhase.waiting);
      expect(api.polls, ['k1', 'k2']);
      login.dispose();
    });
  });

  test('§8.3 unanswered polls back off 2× and 3×; the third in a row stops', () {
    fakeAsync((async) {
      final api = FakeBilibiliLogin()
        ..answers.addAll([
          const NetworkFailure('bilibili', 'offline'),
          const RateLimited('bilibili'),
          const NetworkFailure('bilibili', 'offline'),
        ]);
      final login = BilibiliQrLogin(api: api, save: (_, _) async {});
      unawaited(login.start());
      async.elapse(interval);
      expect(api.polls, hasLength(1));
      async.elapse(interval * 2 - const Duration(milliseconds: 1));
      expect(api.polls, hasLength(1), reason: 'second poll after 2×');
      async.elapse(const Duration(milliseconds: 1));
      expect(api.polls, hasLength(2));
      async.elapse(interval * 3);
      expect(api.polls, hasLength(3));
      expect(login.phase, QrLoginPhase.failed);
      expect(login.message, contains('检查扫码状态失败'));
      async.elapse(interval * 10);
      expect(api.polls, hasLength(3));
      login.dispose();
    });
  });

  test('§8.3 an answer resets the failure count; ApiChanged fails at once', () {
    fakeAsync((async) {
      final api = FakeBilibiliLogin()
        ..answers.addAll([
          const NetworkFailure('bilibili', 'offline'),
          (state: BilibiliQrState.scanned, cookie: null),
          const ApiChanged('bilibili', 'qrcode/poll: code 86000'),
        ]);
      final login = BilibiliQrLogin(api: api, save: (_, _) async {});
      unawaited(login.start());
      async.elapse(interval + interval * 2);
      expect(login.phase, QrLoginPhase.scanned);
      async.elapse(interval);
      expect(login.phase, QrLoginPhase.failed);
      expect(api.polls, hasLength(3));
      login.dispose();
    });
  });

  test('§8.2 a confirmed cookie that does not verify is not stored', () {
    fakeAsync((async) {
      final api = FakeBilibiliLogin()
        ..answers.add((state: BilibiliQrState.confirmed, cookie: 'SESSDATA=bad'))
        ..accountAnswer = const NeedsLogin('bilibili', 'code -101');
      var saved = 0;
      final login = BilibiliQrLogin(api: api, save: (_, _) async => saved++);
      unawaited(login.start());
      async.elapse(interval);
      expect(login.phase, QrLoginPhase.failed);
      expect(login.message, contains('登录校验没有通过'));
      expect(saved, 0);
      login.dispose();
    });
  });

  test('§8.3 a refresh voids the old code’s poll in flight', () {
    fakeAsync((async) {
      final slow = Completer<QrPoll>();
      final api = _SlowLogin(slow);
      final login = BilibiliQrLogin(api: api, save: (_, _) async {});
      unawaited(login.start());
      async.elapse(interval);
      unawaited(login.start());
      async.flushMicrotasks();
      slow.complete((state: BilibiliQrState.expired, cookie: null));
      async.flushMicrotasks();
      expect(login.phase, QrLoginPhase.waiting, reason: 'the old answer is ignored');
      login.dispose();
    });
  });

  test('disposing stops every timer', () {
    fakeAsync((async) {
      final api = FakeBilibiliLogin();
      BilibiliQrLogin(api: api, save: (_, _) async {})
        ..start().ignore()
        ..dispose();
      async.elapse(interval * 5);
      expect(api.polls, isEmpty);
      expect(async.pendingTimers, isEmpty);
    });
  });
}

/// The first poll waits for [first]; later polls answer "waiting".
class _SlowLogin extends FakeBilibiliLogin {
  new(this.first);

  final Completer<QrPoll> first;

  @override
  Future<QrPoll> qrPoll(String key) {
    polls.add(key);
    return polls.length == 1 ? first.future : Future.value((state: BilibiliQrState.waiting, cookie: null));
  }
}
