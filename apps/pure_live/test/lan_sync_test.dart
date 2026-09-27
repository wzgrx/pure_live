import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/sync/lan_sync.dart';

const _device = LanDevice(id: 'd1', name: '客厅电视', platform: 'android', version: '4.0.0');

void main() {
  group('protocol', () {
    test('codes are six digits and compared exactly', () {
      final code = LanSyncProtocol.newCode(Random(1));
      expect(code, matches(RegExp(r'^\d{6}$')));
      expect(LanSyncProtocol.codesMatch('123456', '123 456'), isTrue);
      expect(LanSyncProtocol.codesMatch('123456', '123457'), isFalse);
      expect(LanSyncProtocol.codesMatch('123456', '12345'), isFalse);
      expect(LanSyncProtocol.codesMatch('', ''), isFalse);
      expect(LanSyncProtocol.codesMatch('123456', null), isFalse);
    });

    test('reads typed addresses and the 3.x QR text', () {
      final qr = LanSyncProtocol.qrUri(host: '192.168.1.5', port: 39888, code: '012345');
      expect(qr.toString(), 'purelive://192.168.1.5:39888/sync?code=012345');
      expect(LanSyncProtocol.parseTarget(qr.toString()), const LanTarget('192.168.1.5', 39888, code: '012345'));
      expect(LanSyncProtocol.parseTarget(' 192.168.1.5 '), const LanTarget('192.168.1.5', 39888));
      expect(LanSyncProtocol.parseTarget('192.168.1.5:40000'), const LanTarget('192.168.1.5', 40000));
      expect(LanSyncProtocol.parseTarget('http://tv.local:39889'), const LanTarget('tv.local', 39889));
      expect(LanSyncProtocol.parseTarget('purelive://10.0.0.2:39888/sync?code=12'), const LanTarget('10.0.0.2', 39888));
      expect(LanSyncProtocol.parseTarget('打开 设置'), isNull);
      expect(LanSyncProtocol.parseTarget(''), isNull);
    });
  });

  group('receiver and sender', () {
    late IoLiveHttp http;
    late LanSyncSender sender;
    final receivers = <LanSyncReceiver>[];

    setUp(() {
      http = IoLiveHttp();
      sender = LanSyncSender(http, timeout: const Duration(seconds: 10));
    });

    tearDown(() async {
      http.close();
      for (final receiver in receivers) {
        await receiver.stop();
      }
      receivers.clear();
    });

    Future<(LanSyncReceiver, LanTarget)> start(LanPackageHandler handler, {int maxFailures = 5}) async {
      final receiver = LanSyncReceiver(
        handler: handler,
        device: _device,
        preferredPort: 0,
        maxFailures: maxFailures,
        maxBodyBytes: 64 * 1024,
      );
      receivers.add(receiver);
      final port = await receiver.start();
      return (receiver, LanTarget('127.0.0.1', port));
    }

    Map<String, Object?> package([Map<String, Object?>? backup]) =>
        LanSyncProtocol.package(backup ?? {'format': 'pure_live.backup', 'version': 4}, from: _device);

    test('the status answers without a code and never leaks it', () async {
      final (receiver, target) = await start((_) async => LanDecision.applied);
      final status = await sender.status(target);
      expect(status?.name, '客厅电视');
      final raw = await http.send(LiveRequest(site: 'lan', url: target.statusUrl));
      expect(raw.text, isNot(contains(receiver.code)));
      expect(raw.header('access-control-allow-origin'), isNull);
    });

    test('a wrong code is refused before the user is asked, and repeated failures change the code', () async {
      var asked = 0;
      final (receiver, target) = await start((_) async {
        asked++;
        return LanDecision.applied;
      }, maxFailures: 3);
      final first = receiver.code;
      final wrong = first == '000000' ? '111111' : '000000';
      for (var i = 0; i < 2; i++) {
        expect(await sender.send(target, wrong, package()), LanSendResult.wrongCode);
      }
      expect(receiver.code, first);
      expect(await sender.send(target, wrong, package()), LanSendResult.wrongCode);
      expect(receiver.code, isNot(first), reason: 'the third failure rotates the code');
      expect(await sender.send(target, first, package()), LanSendResult.wrongCode);
      expect(asked, 0);
    });

    test('the receiving user decides; the code works once', () async {
      final decisions = [LanDecision.rejected, LanDecision.applied];
      final seen = <LanIncoming>[];
      final (receiver, target) = await start((incoming) async {
        seen.add(incoming);
        return decisions.removeAt(0);
      });
      var code = receiver.code;
      expect(await sender.send(target, code, package()), LanSendResult.rejected);
      expect(receiver.code, isNot(code), reason: 'a decision uses the code up');
      expect(await sender.send(target, code, package()), LanSendResult.wrongCode);
      code = receiver.code;
      expect(await sender.send(target, code, package()), LanSendResult.applied);
      expect(seen, hasLength(2));
      expect(seen.first.sender?.name, '客厅电视');
      expect(seen.first.remoteAddress, '127.0.0.1');
      expect(seen.first.document['type'], 'pure_live_sync');
      expect(seen.first.document['version'], 2);
    });

    test('one package at a time', () async {
      final waiting = Completer<LanDecision>();
      final (receiver, target) = await start((_) => waiting.future);
      final code = receiver.code;
      final first = sender.send(target, code, package());
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await sender.send(target, code, package()), LanSendResult.busy);
      waiting.complete(LanDecision.applied);
      expect(await first, LanSendResult.applied);
    });

    test('refuses web pages, oversized bodies, other methods and non-sync JSON', () async {
      final (receiver, target) = await start((_) async => LanDecision.applied);
      final fromBrowser = await http.send(
        LiveRequest(
          site: 'lan',
          url: target.settingsUrl,
          method: 'POST',
          headers: {'origin': 'http://evil.example', LanSyncProtocol.pairingHeader: receiver.code},
          body: utf8.encode(jsonEncode(package())),
        ),
      );
      expect(fromBrowser.status, 403);
      expect(fromBrowser.header('access-control-allow-origin'), isNull);

      final pull = await http.send(
        LiveRequest(site: 'lan', url: target.settingsUrl, headers: {LanSyncProtocol.pairingHeader: receiver.code}),
      );
      expect(pull.status, 405);

      final huge = package({'format': 'pure_live.backup', 'pad': 'x' * (70 * 1024)});
      expect(await sender.send(target, receiver.code, huge), LanSendResult.unsupported);
      expect(await sender.send(target, receiver.code, {'type': 'something_else'}), LanSendResult.unsupported);
    });

    test('an unreachable receiver', () async {
      final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close(force: true);
      expect(await sender.send(LanTarget('127.0.0.1', port), '123456', package()), LanSendResult.unreachable);
    });

    test('a v4 package from one store is planned and applied on another after confirmation', () async {
      final phone = await LiveStore.inMemory();
      final tv = await LiveStore.inMemory();
      addTearDown(phone.close);
      addTearDown(tv.close);
      final phoneSecrets = await SecretStore.memory({SecretRefs.cookie('bilibili'): 'SESSDATA=phone'});
      final tvSecrets = await SecretStore.memory();
      await phone.follows.follow(RoomSnapshot(ref: RoomRef('bilibili', '21495945'), anchorName: '主播'));
      await phone.settings.set(Settings.danmakuSpeed, 180);

      final tvBackup = BackupService(tv, secrets: tvSecrets, kdfIterations: 1000);
      ImportReport? planned;
      final (receiver, target) = await start((incoming) async {
        // What the confirmation dialog does: dry run first, then the
        // passphrase for the encrypted accounts section, then one write.
        final dryRun = await tvBackup.plan(incoming.document);
        planned = dryRun.report;
        final plan = await tvBackup.plan(incoming.document, passphrase: 'correct horse');
        await tvBackup.apply(plan);
        return LanDecision.applied;
      });

      final document = await BackupService(
        phone,
        secrets: phoneSecrets,
        kdfIterations: 1000,
      ).export(passphrase: 'correct horse');
      final result = await sender.send(target, receiver.code, LanSyncProtocol.package(document, from: _device));
      expect(result, LanSendResult.applied);
      expect(planned!.format, 'v4');
      expect(planned!.secretsPresent, isTrue);
      expect(planned!.secretsSkipped, isTrue, reason: 'locked until the passphrase is given');
      expect((await tv.follows.all()).single.room.ref, RoomRef('bilibili', '21495945'));
      expect(tv.settings.get(Settings.danmakuSpeed), 180);
      expect(tvSecrets.cookieFor('bilibili'), 'SESSDATA=phone');
      // Without a passphrase the cookie never travels in clear text.
      expect(jsonEncode(document), isNot(contains('SESSDATA=phone')));
    });

    test('a 3.x package (version 1) reaches the handler and plans as v3', () async {
      final tv = await LiveStore.inMemory();
      addTearDown(tv.close);
      ImportReport? planned;
      final (receiver, target) = await start((incoming) async {
        planned = (await BackupService(tv).plan(incoming.document, mode: RestoreMode.follows)).report;
        return LanDecision.rejected;
      });
      final legacy = {
        'type': 'pure_live_sync',
        'version': 1,
        'settings': {
          'backupVersion': 3,
          'favorite': {
            'favoriteRooms': [
              {'platform': 'douyu', 'roomId': '5526219', 'nick': '主播'},
            ],
          },
        },
      };
      expect(await sender.send(target, receiver.code, legacy), LanSendResult.rejected);
      expect(planned?.format, 'v3');
      expect(planned?.counts['follows']?.read, 1);
      expect(await tv.follows.count(), 0, reason: 'rejected: nothing written');
    });
  });
}
