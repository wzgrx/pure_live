import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/recording.dart';
import 'package:pure_live_app/core/store.dart';

/// Keys of the rooms the recorder is saving now (preparing, recording or
/// reconnecting): the "录制中" mark on cards and rows (spec/product.md
/// F-FAV-01). Waiting for a broadcast is not recording.
final StreamProvider<Set<String>> recordingRoomsProvider = StreamProvider<Set<String>>((ref) {
  final manager = ref.watch(recordManagerProvider);
  Set<String> current() => {
    for (final task in manager.tasks)
      if (showsRecording(task)) task.key,
  };
  late final StreamController<Set<String>> controller;
  var last = current();
  void update(Object? _) {
    final next = current();
    if (next.length == last.length && next.containsAll(last)) return;
    last = next;
    controller.add(next);
  }

  final subscriptions = <StreamSubscription<Object?>>[];
  controller = StreamController<Set<String>>(
    onListen: () {
      controller.add(last);
      subscriptions
        ..add(manager.updates.listen(update))
        ..add(manager.listChanges.listen(update));
    },
    onCancel: () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    },
  );
  ref.onDispose(controller.close);
  return controller.stream;
});

/// Whether [task] makes its room show "录制中".
bool showsRecording(RecordTask task) => task.state.holdsSlot;

/// The cover cache period of live cards (spec/product.md F-FAV-04): null
/// while covers keep their cached image; otherwise the index of the current
/// interval since the epoch. Live covers put it in their cache key, so every
/// interval downloads them again; the old image stays until the new one
/// arrives. Wall-clock periods keep a restart from reusing an old period.
class CoverPeriod extends Notifier<int?> {
  Timer? _timer;

  @override
  int? build() {
    final settings = ref.watch(storeProvider).settings;
    final changes = settings.changes
        .where({Settings.autoRefreshCovers.id, Settings.coverRefreshInterval.id}.contains)
        .listen((_) => ref.invalidateSelf());
    ref.onDispose(() {
      _timer?.cancel();
      unawaited(changes.cancel());
    });
    if (!settings.get(Settings.autoRefreshCovers)) return null;
    return _schedule(Duration(minutes: settings.get(Settings.coverRefreshInterval)));
  }

  int _schedule(Duration period) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final index = now ~/ period.inMilliseconds;
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: (index + 1) * period.inMilliseconds - now), () {
      state = _schedule(period);
    });
    return index;
  }
}

/// See [CoverPeriod].
final coverPeriodProvider = NotifierProvider<CoverPeriod, int?>(CoverPeriod.new);
