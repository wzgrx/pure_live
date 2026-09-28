import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

LiveMessage _message(
  String text, {
  String user = 'u1',
  bool local = false,
  LiveMessageType type = LiveMessageType.chat,
}) =>
    LiveMessage(type: type, userName: user, userId: user, message: text, color: LiveMessageColor.white, isLocal: local);

const _window = Duration(seconds: 5);

void main() {
  final start = DateTime(2026, 8, 19, 12);
  DateTime at(int milliseconds) => start.add(Duration(milliseconds: milliseconds));

  // 3.x test/repeated_danmaku_filter_test.dart.
  test('collapses identical audience text across users only inside the configured window', () {
    final filter = RepeatedDanmakuFilter();
    expect(filter.accepts(_message('  加油  '), enabled: true, window: _window, now: start), isTrue);
    expect(
      filter.accepts(
        _message('加油', user: 'u2'),
        enabled: true,
        window: _window,
        now: at(2000),
      ),
      isFalse,
    );
    expect(
      filter.accepts(
        _message('加油', user: 'u3'),
        enabled: true,
        window: _window,
        now: at(8000),
      ),
      isTrue,
    );
  });

  test('local messages bypass repeated-text filtering and disabling clears stale entries', () {
    final filter = RepeatedDanmakuFilter();
    expect(filter.accepts(_message('hello'), enabled: true, window: _window, now: start), isTrue);
    expect(
      filter.accepts(
        _message('hello', user: 'local', local: true),
        enabled: true,
        window: _window,
        now: at(1000),
      ),
      isTrue,
    );
    expect(
      filter.accepts(
        _message('hello', user: 'u2'),
        enabled: false,
        window: _window,
        now: at(2000),
      ),
      isTrue,
    );
    expect(
      filter.accepts(
        _message('hello', user: 'u3'),
        enabled: true,
        window: _window,
        now: at(3000),
      ),
      isTrue,
    );
  });

  // Derived from the 3.x code.
  test('whitespace runs count as one space and case is ignored', () {
    final filter = RepeatedDanmakuFilter();
    expect(filter.accepts(_message('Nice  Shot\t!'), enabled: true, window: _window, now: start), isTrue);
    expect(filter.accepts(_message('nice shot !'), enabled: true, window: _window, now: at(1)), isFalse);
    expect(filter.accepts(_message('niceshot!'), enabled: true, window: _window, now: at(2)), isTrue);
  });

  test('emoji must match exactly', () {
    final filter = RepeatedDanmakuFilter();
    expect(filter.accepts(_message('好😀'), enabled: true, window: _window, now: start), isTrue);
    expect(filter.accepts(_message('好😁'), enabled: true, window: _window, now: at(1)), isTrue);
    expect(filter.accepts(_message('好😀'), enabled: true, window: _window, now: at(2)), isFalse);
  });

  test('the window is inclusive and slides with every sighting', () {
    final filter = RepeatedDanmakuFilter();
    expect(filter.accepts(_message('666'), enabled: true, window: _window, now: start), isTrue);
    expect(filter.accepts(_message('666'), enabled: true, window: _window, now: at(5000)), isFalse);
    expect(
      filter.accepts(_message('666'), enabled: true, window: _window, now: at(9000)),
      isFalse,
      reason: 'slid',
    );
    expect(filter.accepts(_message('666'), enabled: true, window: _window, now: at(14001)), isTrue);
  });

  test('other types, empty text and local messages always pass', () {
    final filter = RepeatedDanmakuFilter();
    for (var index = 0; index < 2; index++) {
      expect(
        filter.accepts(
          _message('x', type: LiveMessageType.superChat),
          enabled: true,
          window: _window,
          now: start,
        ),
        isTrue,
      );
      expect(filter.accepts(_message('   '), enabled: true, window: _window, now: start), isTrue);
      expect(filter.accepts(_message('me', local: true), enabled: true, window: _window, now: start), isTrue);
    }
  });

  test('the oldest text goes first when the filter is full; clear forgets all', () {
    final filter = RepeatedDanmakuFilter(maxEntries: 2);
    for (final text in ['a', 'b', 'c']) {
      filter.accepts(_message(text), enabled: true, window: _window, now: start);
    }
    expect(filter.accepts(_message('a'), enabled: true, window: _window, now: start), isTrue);
    expect(filter.accepts(_message('c'), enabled: true, window: _window, now: start), isFalse);
    filter.clear();
    expect(filter.accepts(_message('c'), enabled: true, window: _window, now: start), isTrue);
  });
}
