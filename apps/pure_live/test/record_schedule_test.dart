import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/recording/record_schedule.dart';

final class _Recorder implements ScheduleRecorder {
  final events = <String>[];
  bool alreadyRecording = false;

  @override
  Future<bool> start(RoomRef room) async {
    events.add('start ${room.key}');
    return !alreadyRecording;
  }

  @override
  Future<void> stop(RoomRef room) async => events.add('stop ${room.key}');
}

void main() {
  late LiveStore store;
  late _Recorder recorder;
  late ProviderContainer container;

  setUp(() async {
    store = await LiveStore.inMemory();
    recorder = _Recorder();
    container = ProviderContainer(
      overrides: [storeProvider.overrideWithValue(store), scheduleRecorderProvider.overrideWithValue(recorder)],
    );
  });

  tearDown(() async {
    container.dispose();
    await store.close();
  });

  ScheduledRecording booking(int startMs, int stopMs, {String id = 'CCTV-1'}) {
    final now = DateTime.now().toUtc();
    return ScheduledRecording(
      room: RoomRef('iptv', id),
      title: '新闻联播',
      start: now.add(Duration(milliseconds: startMs)),
      stop: now.add(Duration(milliseconds: stopMs)),
    );
  }

  test('F-IPTV-10: a booking starts and stops the recorder, then leaves the list', () async {
    final schedule = container.read(recordScheduleProvider.notifier);
    expect(await schedule.add(booking(100, 400)), isTrue);
    expect(container.read(recordScheduleProvider), hasLength(1));
    expect(await store.meta.get(RecordScheduleNotifier.metaKey), contains('新闻联播'));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(recorder.events, ['start iptv:CCTV-1']);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(recorder.events, ['start iptv:CCTV-1', 'stop iptv:CCTV-1']);
    expect(container.read(recordScheduleProvider), isEmpty);
    expect(await store.meta.get(RecordScheduleNotifier.metaKey), isNull);
  });

  test('a recording the user started keeps running; a past window is refused', () async {
    recorder.alreadyRecording = true;
    final schedule = container.read(recordScheduleProvider.notifier);
    expect(await schedule.add(booking(-1000, -10)), isFalse);
    expect(await schedule.add(booking(0, 200)), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(recorder.events, ['start iptv:CCTV-1'], reason: 'not stopped: the schedule did not start it');
  });

  test('cancelling stops what the booking started; the list survives a restart', () async {
    final schedule = container.read(recordScheduleProvider.notifier);
    final running = booking(0, 60000);
    await schedule.add(running);
    await schedule.add(booking(60000, 120000, id: 'CCTV-2'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await schedule.remove(running);
    expect(recorder.events, ['start iptv:CCTV-1', 'stop iptv:CCTV-1']);

    final restarted = ProviderContainer(
      overrides: [storeProvider.overrideWithValue(store), scheduleRecorderProvider.overrideWithValue(_Recorder())],
    );
    addTearDown(restarted.dispose);
    await restarted.read(recordScheduleProvider.notifier).restore();
    expect(restarted.read(recordScheduleProvider).map((item) => item.room.roomId), ['CCTV-2']);
  });
}
