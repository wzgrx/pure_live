import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

/// A platform whose runs are driven by the test.
final class _Fake extends DanmakuConnectionBase<String> {
  new() : super(heartbeatInterval: const Duration(seconds: 45));

  final List<DanmakuRun> runs = [];
  final List<String> started = [];
  final List<String> log = [];
  Completer<void>? hold;
  Exception? failure;

  @override
  Future<void> start(String args, DanmakuRun run) async {
    runs.add(run);
    started.add(args);
    log.add('start $args');
    final hold = this.hold;
    if (hold != null) await hold.future;
    final failure = this.failure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> stop() async => log.add('stop');
}

LiveMessage _chat(String text) =>
    LiveMessage(type: LiveMessageType.chat, userName: 'u', message: text, color: LiveMessageColor.white);

List<DanmakuEvent> _record(DanmakuConnection connection) {
  final events = <DanmakuEvent>[];
  connection.events.listen(events.add);
  return events;
}

void main() {
  group('DanmakuConnectionBase', () {
    test('reports ready, messages, reconnects and the final close in order', () async {
      final connection = _Fake();
      final events = _record(connection);
      expect(connection.status, DanmakuStatus.idle);
      expect(connection.heartbeatInterval, const Duration(seconds: 45));

      await connection.connect('room');
      expect(connection.status, DanmakuStatus.connecting);
      final run = connection.runs.single..ready();
      expect(connection.isConnected, isTrue);
      run
        ..message(_chat('hi'))
        ..reconnecting(DanmakuInterruption.disconnected);
      expect(connection.status, DanmakuStatus.reconnecting);
      expect(connection.isConnected, isFalse);
      run
        ..ready()
        ..closed(DanmakuCloseReason.reconnectsExhausted, detail: 'refused');
      expect(connection.status, DanmakuStatus.closed);

      expect(events, [
        const DanmakuReady(),
        isA<DanmakuReceived>().having((event) => event.message.message, 'text', 'hi'),
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuReady(),
        const DanmakuClosed(DanmakuCloseReason.reconnectsExhausted, detail: 'refused'),
      ]);
    });

    test('reported texts and names lose invisible placeholders; clean messages pass as they are', () async {
      final connection = _Fake();
      final events = _record(connection);
      await connection.connect('room');
      final clean = _chat('[笑哭] 好');
      final start = DateTime.utc(2026, 10);
      connection.runs.single
        ..message(clean)
        ..message(
          LiveMessage(
            type: LiveMessageType.chat,
            userName: '观众\uFFFC',
            message: '\uFFFC晚上好\u0008',
            color: const LiveMessageColor(1, 2, 3),
            userId: '7',
            fansName: '粉\uFFFC丝',
            messageId: 'm1',
            sentAt: start,
            replayed: true,
          ),
        )
        ..message(
          LiveMessage(
            type: LiveMessageType.superChat,
            userName: 'SUPER_CHAT_MESSAGE',
            message: 'SUPER_CHAT_MESSAGE',
            color: LiveMessageColor.white,
            data: LiveSuperChatMessage(
              userName: '老板\uFFFC',
              face: 'f',
              message: '谢谢\uFFFC',
              price: 30,
              startTime: start,
              endTime: start,
              backgroundColor: '#fff',
              backgroundBottomColor: '#000',
              messageId: 's1',
            ),
          ),
        );
      final messages = [for (final event in events.cast<DanmakuReceived>()) event.message];
      expect(messages.first, same(clean));
      final chat = messages[1];
      expect((chat.message, chat.userName, chat.fansName), ('晚上好', '观众', '粉丝'));
      expect(
        (chat.userId, chat.messageId, chat.sentAt, chat.replayed, chat.color),
        ('7', 'm1', start, true, const LiveMessageColor(1, 2, 3)),
      );
      final paid = messages[2].data! as LiveSuperChatMessage;
      expect((paid.userName, paid.message, paid.price, paid.messageId), ('老板', '谢谢', 30, 's1'));
    });

    test('events arrive synchronously, while the platform reports them', () async {
      final connection = _Fake();
      final events = _record(connection);
      await connection.connect('room');
      connection.runs.single.message(_chat('now'));
      expect(events, hasLength(1));
    });

    test('nothing is reported after close; closing twice or before connecting is harmless', () async {
      final connection = _Fake();
      final events = _record(connection);
      await connection.close();
      await connection.connect('room');
      final run = connection.runs.single..ready();
      await connection.close();
      await connection.close();
      run
        ..message(_chat('late'))
        ..reconnecting(DanmakuInterruption.disconnected)
        ..ready()
        ..closed(DanmakuCloseReason.connectionFailed);
      expect(events, [const DanmakuReady()]);
      expect(connection.status, DanmakuStatus.idle);
      expect(run.isActive, isFalse);
      expect(connection.log, ['stop', 'stop', 'start room', 'stop', 'stop']);
    });

    test('after the final close the run is over and its transport released', () async {
      final connection = _Fake();
      final events = _record(connection);
      await connection.connect('room');
      final run = connection.runs.single..closed(DanmakuCloseReason.reconnectsExhausted);
      await pumpEventQueue();
      run.message(_chat('late'));
      expect(events, [const DanmakuClosed(DanmakuCloseReason.reconnectsExhausted)]);
      expect(connection.log.last, 'stop');
      expect(connection.status, DanmakuStatus.closed);

      await connection.connect('room');
      connection.runs.last.ready();
      expect(connection.isConnected, isTrue, reason: 'connect starts over');
    });

    test('connecting again stops the previous room first and silences it', () async {
      final connection = _Fake();
      final events = _record(connection);
      await connection.connect('a');
      final first = connection.runs.single;
      var ended = false;
      unawaited(first.ended.then((_) => ended = true));
      await connection.connect('b');
      first.message(_chat('from a'));
      connection.runs.last.message(_chat('from b'));
      await pumpEventQueue();
      expect(ended, isTrue);
      expect(connection.log, ['stop', 'start a', 'stop', 'start b']);
      expect(events.cast<DanmakuReceived>().map((event) => event.message.message), ['from b']);
    });

    test('close during a pending start silences it and lets connect complete', () async {
      final connection = _Fake()..hold = Completer<void>();
      final events = _record(connection);
      final connecting = connection.connect('room');
      await pumpEventQueue();
      await connection.close();
      connection.runs.single.ready();
      connection.hold!.complete();
      await connecting;
      expect(events, isEmpty);
      expect(connection.status, DanmakuStatus.idle);
    });

    test('a known reason not to start becomes the final close; connect completes', () async {
      final connection = _Fake()..failure = const DanmakuStartFailure(DanmakuCloseReason.credentialsUnavailable);
      final events = _record(connection);
      await connection.connect('room');
      expect(events, [const DanmakuClosed(DanmakuCloseReason.credentialsUnavailable)]);
      expect(connection.status, DanmakuStatus.closed);
    });

    test('another failure is thrown to the caller and the run released', () async {
      final connection = _Fake()..failure = const FormatException('no stream id');
      final events = _record(connection);
      await expectLater(connection.connect('room'), throwsFormatException);
      expect(connection.status, DanmakuStatus.idle);
      expect(connection.runs.single.isActive, isFalse);
      expect(connection.log.last, 'stop');
      expect(events, isEmpty);
    });

    test('a failure of a run already replaced is not thrown', () async {
      final connection = _Fake()
        ..hold = Completer<void>()
        ..failure = const FormatException('cancelled');
      final connecting = connection.connect('room');
      await pumpEventQueue();
      await connection.close();
      connection.hold!.complete();
      await expectLater(connecting, completes);
    });

    test("arguments of another platform's type are refused before anything stops", () async {
      final connection = _Fake();
      await connection.connect('room');
      await expectLater(connection.connect(42), throwsArgumentError);
      await expectLater(connection.connect(null), throwsArgumentError);
      expect(connection.runs.single.isActive, isTrue);
    });

    test('markDisconnected leaves the joined state without a notice', () async {
      final connection = _Fake();
      final events = _record(connection);
      await connection.connect('room');
      connection.runs.single
        ..ready()
        ..markDisconnected();
      expect(connection.status, DanmakuStatus.connecting);
      expect(events, [const DanmakuReady()]);
    });

    test('delay ends early when the run is stopped', () async {
      final connection = _Fake();
      await connection.connect('room');
      final run = connection.runs.single;
      expect(await run.delay(const Duration(milliseconds: 1)), isTrue);
      final waiting = run.delay(const Duration(minutes: 1));
      await connection.close();
      expect(await waiting.timeout(const Duration(seconds: 1)), isFalse);
      expect(await run.delay(Duration.zero), isFalse);
    });
  });

  group('EmptyDanmakuConnection', () {
    test('never connects or reports, like 3.x EmptyDanmaku', () async {
      final connection = EmptyDanmakuConnection();
      final events = _record(connection);
      await connection.connect(const _AnyArgs());
      await connection.connect(null);
      connection.heartbeat();
      await connection.close();
      await connection.close();
      await pumpEventQueue();
      expect(events, isEmpty);
      expect(connection.isConnected, isFalse);
      expect(connection.status, DanmakuStatus.idle);
      expect(connection.heartbeatInterval, const Duration(seconds: 60));
    });
  });

  group('DanmakuRegistry', () {
    test('finds the factory by platform id; other platforms get the empty connection', () {
      var built = 0;
      final registry = DanmakuRegistry({
        SiteIds.huya: () {
          built++;
          return _Fake();
        },
        ' Douyu ': _Fake.new,
      });
      expect(registry.platforms, [SiteIds.douyu, SiteIds.huya], reason: 'display order');
      expect(registry.supports('HUYA'), isTrue);
      expect(registry.supports(SiteIds.cc), isFalse);
      final first = registry.connectionFor('huya');
      final second = registry.connectionFor(' huya');
      expect(first, isA<_Fake>());
      expect(identical(first, second), isFalse, reason: 'a new connection per room page, like 3.x getDanmaku()');
      expect(built, 2);
      expect(registry.connectionFor(SiteIds.acfun), isA<EmptyDanmakuConnection>());
      expect(registry.connectionFor('unknown'), isA<EmptyDanmakuConnection>());
    });

    test('refuses ids that are not platforms, or given twice', () {
      expect(() => DanmakuRegistry({'huajiao': _Fake.new}), throwsArgumentError);
      expect(() => DanmakuRegistry({'huya': _Fake.new, 'Huya': _Fake.new}), throwsArgumentError);
    });

    test('the empty table has no platforms yet', () {
      final registry = DanmakuRegistry.empty();
      expect(registry.platforms, isEmpty);
      for (final id in SiteIds.supported) {
        expect(registry.supports(id), isFalse);
        expect(registry.connectionFor(id), isA<EmptyDanmakuConnection>());
      }
    });
  });
}

/// Any platform data: the empty connection accepts everything.
final class _AnyArgs {
  const new();
}
