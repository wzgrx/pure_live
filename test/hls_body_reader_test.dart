import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/hls_body_reader.dart';

void main() {
  test('unread response cancellation subscribes once and awaits upstream cleanup', () async {
    var listens = 0;
    var cancellations = 0;
    final gate = Completer<void>();
    final stream = StreamController<List<int>>(
      onListen: () => listens++,
      onCancel: () {
        cancellations++;
        return gate.future;
      },
    );
    final reader = HlsBodyReader(stream.stream);
    var done = false;
    final cancel = reader.cancel();
    expect(identical(reader.cancel(), cancel), true);
    final completion = cancel.then((_) => done = true);
    await Future<void>.delayed(Duration.zero);
    expect(listens, 1);
    expect(cancellations, 1);
    expect(done, false);
    gate.complete();
    await completion;
    await stream.close();
    expect(await reader.moveNext(), false);
  });
  test('pending first read is cancelled without a second subscription', () async {
    var listens = 0;
    var cancellations = 0;
    final stream = StreamController<List<int>>(onListen: () => listens++, onCancel: () => cancellations++);
    final reader = HlsBodyReader(stream.stream);
    final pending = reader.moveNext();
    await reader.cancel();
    expect(await pending, false);
    expect(listens, 1);
    expect(cancellations, 1);
    await stream.close();
  });
  test('normal data and stream failure keep iterator semantics', () async {
    final reader = HlsBodyReader(
      Stream.fromIterable([
        [1],
        [2, 3],
      ]),
    );
    final bytes = <int>[];
    while (await reader.moveNext()) {
      bytes.addAll(reader.current);
    }
    expect(bytes, [1, 2, 3]);
    await reader.cancel();
    final failed = HlsBodyReader(Stream.error(StateError('Read fixture error')));
    await expectLater(failed.moveNext(), throwsStateError);
    await failed.cancel();
  });
}
