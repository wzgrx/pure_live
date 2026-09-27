import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/live_play/widgets/danmaku/danmaku_arrival_counter.dart';

void main() {
  test('a full history counts every arrival in the next batch', () {
    final counter = DanmakuArrivalCounter<Object>();
    final old = List.generate(500, (_) => Object());
    counter.update(old);
    expect(counter.update([...old.skip(3), Object(), Object(), Object()]), 3);
  });

  test('blocking the newest message and clearing history are not arrivals', () {
    final counter = DanmakuArrivalCounter<Object>();
    final old = [Object(), Object()];
    counter.update(old);
    expect(counter.update([old.first]), 0);
    expect(counter.update([]), 0);
  });

  test('unchanged and reordered snapshots do not add arrivals', () {
    final counter = DanmakuArrivalCounter<Object>();
    final messages = [Object(), Object()];
    expect(counter.update(messages), 2);
    expect(counter.update(messages), 0);
    expect(counter.update(messages.reversed.toList()), 0);
  });

  test('a replaced batch counts all distinct message objects', () {
    final counter = DanmakuArrivalCounter<Object>();
    counter.update([Object(), Object()]);
    expect(counter.update([Object(), Object(), Object()]), 3);
  });
}
