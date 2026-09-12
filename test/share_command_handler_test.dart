import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/utils/share_command_handler.dart';
import 'package:pure_live/plugins/share_command_handler.dart';

void main() {
  test('clipboard command is retried when its consumer fails before accepting it', () async {
    final command = _command('share-retry-fixture');
    final handler = ShareCommandHandler(
      readClipboard: () async => command,
      notifySuccess: (_) {},
      notifyFailure: (_) {},
    );

    var attempts = 0;
    await handler.checkClipboard((_) {
      attempts++;
      throw StateError('fixture consumer failed');
    });
    await handler.checkClipboard((_) {
      attempts++;
    });

    expect(attempts, 2);
  });

  test('overlapping clipboard checks share one read and one consumer transaction', () async {
    final command = _command('overlap-fixture');
    final readGate = Completer<String?>();
    var reads = 0;
    var callbacks = 0;
    final handler = ShareCommandHandler(
      readClipboard: () {
        reads++;
        return readGate.future;
      },
      notifySuccess: (_) {},
      notifyFailure: (_) {},
    );

    final first = handler.checkClipboard((_) => callbacks++);
    final second = handler.checkClipboard((_) => callbacks++);
    expect(identical(first, second), isTrue);

    readGate.complete(command);
    await Future.wait([first, second]);
    expect(reads, 1);
    expect(callbacks, 1);
  });

  test('clipboard import ignores signed commands without a usable room identity', () async {
    for (final data in [
      {'platform': '', 'roomId': '123'},
      {'platform': 'bilibili', 'roomId': ''},
      {'platform': 'bilibili', 'roomId': '0'},
      {'platform': 'bilibili', 'roomId': 'undefined'},
    ]) {
      final handler = ShareCommandHandler(
        readClipboard: () async => ShareCommandCodec.encodeShort(data),
        notifySuccess: (_) {},
        notifyFailure: (_) {},
      );
      var imports = 0;
      await handler.checkClipboard((_) => imports++);
      expect(imports, 0, reason: data.toString());
    }
  });

  test('desktop share commits a decodable command and suppresses its trimmed clipboard copy', () async {
    String? clipboard;
    final successes = <String>[];
    final failures = <String>[];
    final handler = ShareCommandHandler(
      isDesktop: () => true,
      readClipboard: () async => clipboard == null ? null : ' \n$clipboard\t',
      writeClipboard: (text) async => clipboard = text,
      notifySuccess: successes.add,
      notifyFailure: failures.add,
    );

    final shared = await handler.onShareRoomPressed(_room('desktop-fixture'));

    expect(shared, isTrue);
    expect(successes, ['copied_to_clipboard']);
    expect(failures, isEmpty);
    expect(ShareCommandCodec.decodeShort(clipboard!), {
      'platform': 'bilibili',
      'roomId': 'desktop-fixture',
      'title': 'Fixture room',
      'nick': 'Fixture anchor',
      'link': 'https://live.bilibili.com/desktop-fixture',
      'cover': '',
      'avatar': '',
    });

    var imports = 0;
    await handler.checkClipboard((_) => imports++);
    expect(imports, 0);
  });

  test('failed desktop clipboard write reports failure and does not blacklist an uncommitted command', () async {
    String? attemptedCommand;
    final failures = <String>[];
    final handler = ShareCommandHandler(
      isDesktop: () => true,
      readClipboard: () async => attemptedCommand,
      writeClipboard: (text) async {
        attemptedCommand = text;
        throw StateError('fixture clipboard write failed');
      },
      notifySuccess: (_) => fail('success feedback must not run'),
      notifyFailure: failures.add,
    );

    final shared = await handler.onShareRoomPressed(_room('write-failure-fixture'));

    expect(shared, isFalse);
    expect(failures, ['share_failed']);
    var imports = 0;
    await handler.checkClipboard((_) => imports++);
    expect(imports, 1);
  });

  test('successful mobile handoff survives an unavailable post-share clipboard', () async {
    var shareCalls = 0;
    final failures = <String>[];
    final handler = ShareCommandHandler(
      isDesktop: () => false,
      shareText: (_) async => shareCalls++,
      readClipboard: () async => throw StateError('fixture clipboard unavailable'),
      notifySuccess: (_) {},
      notifyFailure: failures.add,
    );

    final shared = await handler.onShareRoomPressed(_room('mobile-fixture'));

    expect(shared, isTrue);
    expect(shareCalls, 1);
    expect(failures, isEmpty);
  });

  test('failed mobile handoff is contained and reports one localized failure', () async {
    final failures = <String>[];
    final handler = ShareCommandHandler(
      isDesktop: () => false,
      shareText: (_) async => throw StateError('fixture share sheet failed'),
      notifySuccess: (_) {},
      notifyFailure: failures.add,
    );

    final shared = await handler.onShareRoomPressed(_room('mobile-failure-fixture'));

    expect(shared, isFalse);
    expect(failures, ['share_failed']);
  });

  test('share rejects a room without a usable identity before opening a platform channel', () async {
    final failures = <String>[];
    final handler = ShareCommandHandler(
      isDesktop: () => true,
      writeClipboard: (_) async => fail('invalid room must not reach the clipboard'),
      notifySuccess: (_) {},
      notifyFailure: failures.add,
    );

    final shared = await handler.onShareRoomPressed(LiveRoom(platform: 'bilibili', roomId: '0'));

    expect(shared, isFalse);
    expect(failures, ['share_failed']);
  });

  test('self-share suppression retains only the configured bounded history', () async {
    final commands = <String>[];
    String? clipboard;
    final handler = ShareCommandHandler(
      retainedHashLimit: 2,
      isDesktop: () => true,
      readClipboard: () async => clipboard,
      writeClipboard: (text) async => commands.add(text),
      notifySuccess: (_) {},
      notifyFailure: (_) {},
    );

    for (final roomId in ['bounded-1', 'bounded-2', 'bounded-3']) {
      expect(await handler.onShareRoomPressed(_room(roomId)), isTrue);
    }

    clipboard = commands.first;
    var imports = 0;
    await handler.checkClipboard((_) => imports++);
    expect(imports, 1, reason: 'the oldest self-share must be evicted when the bound is exceeded');

    handler.resetLifecycleCache();
    clipboard = commands.last;
    await handler.checkClipboard((_) => imports++);
    expect(imports, 1, reason: 'the newest self-share must remain suppressed');
  });

  test('retained self-share history requires a positive bound', () {
    expect(() => ShareCommandHandler(retainedHashLimit: 0), throwsA(isA<ArgumentError>()));
  });

  for (final locale in ['zh', 'en']) {
    test('$locale includes share failure feedback', () {
      final translations = jsonDecode(File('assets/translations/$locale.json').readAsStringSync()) as Map;
      expect(translations['share_failed'], isNotEmpty);
    });
  }
}

LiveRoom _room(String roomId) => LiveRoom(
  platform: 'bilibili',
  roomId: roomId,
  title: 'Fixture room',
  nick: 'Fixture anchor',
  link: 'https://live.bilibili.com/$roomId',
);

String _command(String roomId) => ShareCommandCodec.encodeShort({
  'platform': 'bilibili',
  'roomId': roomId,
  'title': 'Fixture room',
  'nick': 'Fixture anchor',
});
