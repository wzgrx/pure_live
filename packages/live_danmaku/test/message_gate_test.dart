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
}) => LiveMessage(
  type: type,
  userName: userName,
  userId: userId,
  message: text,
  messageId: messageId,
  sentAt: sentAt,
  color: LiveMessageColor.white,
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
}
