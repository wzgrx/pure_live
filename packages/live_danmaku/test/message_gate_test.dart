import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

LiveMessage _message({
  String text = 'hello',
  String userId = '1',
  String userName = 'viewer',
  String messageId = '',
  DateTime? sentAt,
  LiveMessageType type = LiveMessageType.chat,
  bool replayed = false,
  Object? data,
}) => LiveMessage(
  type: type,
  userName: userName,
  userId: userId,
  message: text,
  messageId: messageId,
  sentAt: sentAt,
  color: LiveMessageColor.white,
  replayed: replayed,
  data: data,
);

/// A super chat sent at [sentAt], shown until [endTime].
LiveMessage _superChat(DateTime sentAt, DateTime endTime, {String id = '', bool replayed = false}) => _message(
  type: LiveMessageType.superChat,
  messageId: id,
  sentAt: sentAt,
  replayed: replayed,
  data: LiveSuperChatMessage(
    messageId: id,
    userName: 'viewer',
    face: '',
    message: 'hello',
    price: 30,
    startTime: sentAt,
    endTime: endTime,
    backgroundColor: '',
    backgroundBottomColor: '',
  ),
);

void main() {
  final now = DateTime(2026, 8, 17, 12);

  // 3.x test/danmaku_message_gate_test.dart.
  group('3.x cases', () {
    test('rejects a replayed stable platform message id', () {
      final gate = DanmakuMessageGate();
      final message = _message(messageId: 'platform:123', sentAt: now);
      expect(gate.accepts(message, now: now), isTrue);
      expect(gate.accepts(message, now: now.add(const Duration(seconds: 20))), isFalse);
    });

    test('keeps genuine repeated text after the short fallback window', () {
      final gate = DanmakuMessageGate();
      final message = _message();
      expect(gate.accepts(message, now: now), isTrue);
      expect(gate.accepts(message, now: now.add(const Duration(seconds: 1))), isFalse);
      expect(gate.accepts(message, now: now.add(const Duration(seconds: 3))), isTrue);
    });

    test('rejects platform backlog older than the live freshness window', () {
      final gate = DanmakuMessageGate();
      expect(gate.accepts(_message(sentAt: now.subtract(const Duration(minutes: 2))), now: now), isFalse);
    });

    test('bounds retained fingerprints', () {
      final gate = DanmakuMessageGate(maxEntries: 2);
      for (var index = 0; index < 3; index++) {
        expect(gate.accepts(_message(messageId: 'id:$index'), now: now), isTrue);
      }
      expect(gate.accepts(_message(messageId: 'id:0'), now: now), isTrue);
    });
  });

  group('derived from the 3.x code', () {
    test('a platform time exactly 45 s old passes; one more millisecond does not', () {
      final gate = DanmakuMessageGate();
      expect(
        gate.accepts(
          _message(text: 'a', sentAt: now.subtract(const Duration(seconds: 45))),
          now: now,
        ),
        isTrue,
      );
      expect(
        gate.accepts(
          _message(text: 'b', sentAt: now.subtract(const Duration(seconds: 45, milliseconds: 1))),
          now: now,
        ),
        isFalse,
      );
    });

    test('a time up to 10 minutes ahead passes (clock skew); further ahead is malformed', () {
      final gate = DanmakuMessageGate();
      expect(
        gate.accepts(
          _message(text: 'a', sentAt: now.add(const Duration(minutes: 10))),
          now: now,
        ),
        isTrue,
      );
      expect(
        gate.accepts(
          _message(text: 'b', sentAt: now.add(const Duration(minutes: 10, seconds: 1))),
          now: now,
        ),
        isFalse,
      );
    });

    test('an old message is dropped before it is remembered', () {
      final gate = DanmakuMessageGate();
      final stale = _message(messageId: 'x', sentAt: now.subtract(const Duration(minutes: 1)));
      expect(gate.accepts(stale, now: now), isFalse);
      expect(gate.accepts(_message(messageId: 'x'), now: now), isTrue);
    });

    test('a stable id is kept 10 minutes, inclusive', () {
      final gate = DanmakuMessageGate();
      final message = _message(messageId: ' douyu:1 ');
      expect(gate.accepts(message, now: now), isTrue);
      expect(gate.accepts(_message(messageId: 'douyu:1'), now: now.add(const Duration(minutes: 10))), isFalse);
      expect(gate.accepts(message, now: now.add(const Duration(minutes: 10, seconds: 1))), isTrue);
    });

    test('the fallback window is 2.5 s, inclusive, and does not slide', () {
      final gate = DanmakuMessageGate();
      final message = _message();
      expect(gate.accepts(message, now: now), isTrue);
      expect(gate.accepts(message, now: now.add(const Duration(milliseconds: 2000))), isFalse);
      expect(gate.accepts(message, now: now.add(const Duration(milliseconds: 2500))), isFalse);
      expect(
        gate.accepts(message, now: now.add(const Duration(milliseconds: 2501))),
        isTrue,
        reason: 'the rejected repeats did not restart the window',
      );
    });

    test('without an id the key ignores case and spaces of the sender, not of the text', () {
      final gate = DanmakuMessageGate();
      expect(
        gate.accepts(
          _message(userId: 'U1', userName: ' Viewer ', text: ' Hi '),
          now: now,
        ),
        isTrue,
      );
      expect(
        gate.accepts(
          _message(userId: 'u1', text: 'Hi'),
          now: now,
        ),
        isFalse,
      );
      expect(
        gate.accepts(
          _message(userId: 'u1', text: 'hi'),
          now: now,
        ),
        isTrue,
      );
      expect(
        gate.accepts(
          _message(userId: 'u2', text: 'Hi'),
          now: now,
        ),
        isTrue,
      );
    });

    test('the message type is part of the key', () {
      final gate = DanmakuMessageGate();
      expect(gate.accepts(_message(), now: now), isTrue);
      expect(gate.accepts(_message(type: LiveMessageType.gift), now: now), isTrue);
    });

    test('the oldest key goes first when the gate is full', () {
      final gate = DanmakuMessageGate(maxEntries: 2)
        ..accepts(_message(messageId: 'a'), now: now)
        ..accepts(_message(messageId: 'b'), now: now)
        ..accepts(_message(messageId: 'c'), now: now);
      expect(gate.accepts(_message(messageId: 'c'), now: now), isFalse);
      expect(gate.accepts(_message(messageId: 'b'), now: now), isFalse);
      expect(gate.accepts(_message(messageId: 'a'), now: now), isTrue);
    });

    test('clear forgets everything (another room)', () {
      final message = _message(messageId: 'x');
      final gate = DanmakuMessageGate();
      expect(gate.accepts(message, now: now), isTrue);
      expect(gate.accepts(message, now: now), isFalse);
      gate.clear();
      expect(gate.accepts(message, now: now), isTrue);
    });
  });

  group('retractions', () {
    LiveMessage retraction(LiveRetraction target) => LiveMessage(
      type: LiveMessageType.retraction,
      userName: '',
      message: '',
      color: LiveMessageColor.white,
      data: target,
    );

    test('different targets are different messages; the same target is a duplicate', () {
      final gate = DanmakuMessageGate();
      expect(gate.accepts(retraction(const LiveRetraction.message('m1')), now: now), isTrue);
      expect(gate.accepts(retraction(const LiveRetraction.message('m2')), now: now), isTrue);
      expect(gate.accepts(retraction(const LiveRetraction.user('m1')), now: now), isTrue);
      expect(gate.accepts(retraction(const LiveRetraction.all()), now: now), isTrue);
      expect(gate.accepts(retraction(const LiveRetraction.message('m1')), now: now), isFalse);
    });

    test('a retraction does not collide with the message it takes back', () {
      final gate = DanmakuMessageGate();
      expect(gate.accepts(_message(messageId: 'm1'), now: now), isTrue);
      expect(gate.accepts(retraction(const LiveRetraction.message('m1')), now: now), isTrue);
    });
  });

  // M5.F: messages the platform replays (B-26: 17LIVE's resume backlog; B-22:
  // YouTube's pinned Super Chats on joining) and super chats.
  group('replayed messages and super chats (M5.F)', () {
    test('a replayed message may be 135 s old, inclusive; one more millisecond is too old', () {
      final gate = DanmakuMessageGate();
      expect(gate.maxReplayAge, const Duration(seconds: 135));
      expect(gate.maxMessageAge, const Duration(seconds: 45));
      Duration ago(int seconds, [int millis = 0]) => Duration(seconds: seconds, milliseconds: millis);
      expect(
        gate.accepts(
          _message(text: 'a', sentAt: now.subtract(ago(46))),
          now: now,
        ),
        isFalse,
      );
      expect(
        gate.accepts(
          _message(text: 'a', sentAt: now.subtract(ago(46)), replayed: true),
          now: now,
        ),
        isTrue,
      );
      expect(
        gate.accepts(
          _message(text: 'b', sentAt: now.subtract(ago(135)), replayed: true),
          now: now,
        ),
        isTrue,
      );
      expect(
        gate.accepts(
          _message(text: 'c', sentAt: now.subtract(ago(135, 1)), replayed: true),
          now: now,
        ),
        isFalse,
      );
      expect(
        gate.accepts(_message(text: 'd', replayed: true), now: now),
        isTrue,
        reason: 'no time: no age',
      );
    });

    test('the replay limit can be set; the future limit is the same for a replayed message', () {
      final gate = DanmakuMessageGate(maxReplayAge: const Duration(seconds: 60));
      expect(
        gate.accepts(
          _message(text: 'a', sentAt: now.subtract(const Duration(seconds: 60)), replayed: true),
          now: now,
        ),
        isTrue,
      );
      expect(
        gate.accepts(
          _message(text: 'b', sentAt: now.subtract(const Duration(seconds: 61)), replayed: true),
          now: now,
        ),
        isFalse,
      );
      expect(
        gate.accepts(
          _message(text: 'c', sentAt: now.add(const Duration(minutes: 10)), replayed: true),
          now: now,
        ),
        isTrue,
      );
      expect(
        gate.accepts(
          _message(text: 'd', sentAt: now.add(const Duration(minutes: 10, seconds: 1)), replayed: true),
          now: now,
        ),
        isFalse,
      );
    });

    test('a super chat is not dropped for its age before its end time; at the end time the age counts', () {
      final gate = DanmakuMessageGate();
      final twoHours = now.subtract(const Duration(hours: 2));
      expect(gate.accepts(_superChat(twoHours, now.add(const Duration(milliseconds: 1)), id: 'a'), now: now), isTrue);
      expect(
        gate.accepts(_superChat(twoHours, now.add(const Duration(hours: 3)), id: 'b', replayed: true), now: now),
        isTrue,
      );
      expect(
        gate.accepts(_superChat(twoHours, now, id: 'c'), now: now),
        isFalse,
        reason: 'its end time is reached',
      );
      expect(gate.accepts(_superChat(twoHours, now.subtract(const Duration(seconds: 1)), id: 'd'), now: now), isFalse);
      // Ended, the usual limits: 45 s, or 135 s when replayed.
      final minute = now.subtract(const Duration(minutes: 1));
      final ended = now.subtract(const Duration(seconds: 1));
      expect(gate.accepts(_superChat(minute, ended, id: 'e'), now: now), isFalse);
      expect(gate.accepts(_superChat(minute, ended, id: 'f', replayed: true), now: now), isTrue);
      // A time far in the future is malformed, on display or not.
      final future = now.add(const Duration(minutes: 11));
      expect(gate.accepts(_superChat(future, future.add(const Duration(minutes: 5)), id: 'g'), now: now), isFalse);
      // Without ids the text key applies as before.
      expect(gate.accepts(_superChat(twoHours, now.add(const Duration(hours: 1))), now: now), isTrue);
      expect(gate.accepts(_superChat(twoHours, now.add(const Duration(hours: 1))), now: now), isFalse);
    });

    test('only the super chat of the data counts: a super chat message without one keeps the age limit', () {
      final gate = DanmakuMessageGate();
      final old = now.subtract(const Duration(minutes: 1));
      expect(
        gate.accepts(
          _message(type: LiveMessageType.superChat, sentAt: old),
          now: now,
        ),
        isFalse,
      );
      expect(
        gate.accepts(
          _message(type: LiveMessageType.superChat, sentAt: old, data: 30),
          now: now,
        ),
        isFalse,
      );
    });

    test('ids are compared as before: a replayed copy of a message passes once, whichever comes first', () {
      final gate = DanmakuMessageGate();
      final sent = now.subtract(const Duration(seconds: 90));
      expect(
        gate.accepts(
          _message(messageId: 'm1', sentAt: sent, replayed: true),
          now: now,
        ),
        isTrue,
      );
      expect(
        gate.accepts(
          _message(messageId: 'm1', sentAt: sent, replayed: true),
          now: now,
        ),
        isFalse,
      );
      expect(gate.accepts(_message(messageId: 'm2'), now: now), isTrue);
      expect(gate.accepts(_message(messageId: 'm2', replayed: true), now: now), isFalse);
      // A pinned super chat reported on joining, then the same one live.
      final start = now.subtract(const Duration(minutes: 5));
      final end = now.add(const Duration(minutes: 25));
      expect(gate.accepts(_superChat(start, end, id: 'sc', replayed: true), now: now), isTrue);
      expect(gate.accepts(_superChat(start, end, id: 'sc'), now: now), isFalse);
      // Too old even so: dropped before it is remembered.
      final stale = _message(messageId: 'm3', sentAt: now.subtract(const Duration(minutes: 3)), replayed: true);
      expect(gate.accepts(stale, now: now), isFalse);
      expect(gate.accepts(_message(messageId: 'm3'), now: now), isTrue);
    });
  });
}
