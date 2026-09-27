import 'dart:async';
import 'dart:isolate';

import 'package:live_record/src/remux.dart';

/// Runs [inner] in a background isolate (spec §10), so a long remux never
/// takes time from the caller's event loop — the Flutter UI isolate in the
/// app. Progress and cancellation cross the isolate boundary; any failure
/// arrives as a [RemuxException].
///
/// [inner] is copied into the new isolate, so it must be sendable: a
/// `FlvToMp4Remuxer` over the default `IoRecordFiles` is; an in-memory file
/// system is not shared with the caller.
final class IsolateRemuxer implements Remuxer {
  /// Wraps [inner].
  const new(this.inner);

  /// The remuxer that does the work.
  final Remuxer inner;

  @override
  Future<void> remux(RemuxJob job) async {
    final events = ReceivePort();
    SendPort? control;
    var cancel = false;
    var finished = false;
    final subscription = events.listen((message) {
      if (finished) return;
      if (message is SendPort) {
        control = message;
        if (cancel) message.send(null);
      } else if (message is int) {
        job.onProgress(message);
      }
    });
    unawaited(
      job.cancelled.then((_) {
        cancel = true;
        control?.send(null);
      }),
    );
    try {
      final failure = await _run(inner, events.sendPort, job.input, job.output, job.inputBytes);
      if (failure != null) throw failure;
    } finally {
      finished = true;
      await subscription.cancel();
      events.close();
    }
  }

  /// Runs [inner] in a new isolate; returns the failure, or null. A separate
  /// function so the isolate closure captures only sendable values.
  static Future<RemuxException?> _run(Remuxer inner, SendPort send, String input, String output, int inputBytes) =>
      Isolate.run(() async {
        final stop = ReceivePort();
        final cancelled = Completer<void>();
        stop.listen((_) {
          if (!cancelled.isCompleted) cancelled.complete();
        });
        send.send(stop.sendPort);
        try {
          await inner.remux(
            RemuxJob(
              input: input,
              output: output,
              inputBytes: inputBytes,
              onProgress: send.send,
              cancelled: cancelled.future,
            ),
          );
          return null;
        } on RemuxException catch (error) {
          return error;
        } on Object catch (error) {
          return RemuxException('$error');
        } finally {
          stop.close();
        }
      }, debugName: 'remux');
}
