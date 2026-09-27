import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

final _t0 = DateTime.utc(2026, 9, 27, 12);

DanmakuChat _chat(String text, {String name = 'n'}) =>
    DanmakuChat(room: 'r', session: 0, receivedAt: 0, userName: name, text: text);

DanmakuSuperChat _sc(String id, int endSeconds) => DanmakuSuperChat(
  room: 'r',
  session: 0,
  receivedAt: 0,
  id: id,
  userName: 'u',
  text: 't',
  price: 30,
  startAt: _t0,
  endAt: _t0.add(Duration(seconds: endSeconds)),
);

void main() {
  test('LST-1: the history is a 500-line ring buffer reporting increments', () {
    final history = DanmakuHistory();
    final first = history.addAll([for (var i = 0; i < 450; i++) _chat('$i')]);
    expect((first.appended, first.trimmed), (450, 0));
    final second = history.addAll([for (var i = 450; i < 520; i++) _chat('$i')]);
    expect((second.appended, second.trimmed), (70, 20));
    expect(history.length, 500);
    expect((history[0] as DanmakuChat).text, '20');
    expect((history.lines.last as DanmakuChat).text, '519');
  });

  test('LST-3: blocking removes only matching lines and keeps the order', () {
    final history = DanmakuHistory()..addAll([_chat('a'), _chat('b', name: 'Bad'), _chat('c')]);
    final blocks = DanmakuBlockList(users: ['bad']);
    final change = history.removeWhere(blocks.matches);
    expect(change.removed, 1);
    expect(history.lines.map((line) => (line as DanmakuChat).text), ['a', 'c']);
    expect(history.clear().cleared, isTrue);
    expect(history.length, 0);
  });

  test('LST-5: super chats deduplicated, sorted by end, expired at their end time', () {
    final board = SuperChatBoard();
    expect(board.addAll([_sc('a', 60), _sc('b', 30), _sc('a', 60)], _t0), isTrue);
    expect(board.items.map((chat) => chat.id), ['b', 'a']);
    expect(board.nextExpiry, _t0.add(const Duration(seconds: 30)));
    expect(board.addAll([_sc('a', 90)], _t0), isFalse);
    expect(board.addAll([_sc('old', 0)], _t0), isFalse);
    expect(board.expire(_t0.add(const Duration(seconds: 30))), isTrue);
    expect(board.items.map((chat) => chat.id), ['a']);
    board.clear();
    expect(board.nextExpiry, isNull);
  });

  test('LST-7: the same status at most once in 3 s', () {
    final throttle = NoticeThrottle();
    DanmakuSystem notice(DanmakuStatus status) => DanmakuSystem(room: 'r', session: 0, receivedAt: 0, status: status);
    expect(throttle.accepts(notice(DanmakuStatus.reconnecting), _t0), isTrue);
    expect(throttle.accepts(notice(DanmakuStatus.reconnecting), _t0.add(const Duration(seconds: 2))), isFalse);
    expect(throttle.accepts(notice(DanmakuStatus.connected), _t0.add(const Duration(seconds: 2))), isTrue);
    expect(throttle.accepts(notice(DanmakuStatus.reconnecting), _t0.add(const Duration(seconds: 3))), isTrue);
  });
}
