import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_record/testing.dart';
import 'package:test/test.dart';

import 'support/fake_live.dart';
import 'support/ts_live.dart';

final class _Rig {
  new({RecordSettings settings = const RecordSettings(), MemoryRecordTaskStore? store, MemoryRecordFiles? files})
    : store = store ?? MemoryRecordTaskStore(),
      files = files ?? MemoryRecordFiles() {
    remuxer = FakeRemuxer(this.files);
    manager = RecordManager(
      rooms: rooms,
      store: this.store,
      root: '/rec',
      settings: settings,
      files: this.files,
      opener: RecordOpener(flv: (_) => cdn.open),
      remuxer: remuxer,
      chat: chat,
    );
    manager.updates.listen((task) => history.putIfAbsent(task.key, () => []).add(task.state));
  }

  final rooms = FakeRooms(lines: const ['hw']);
  final cdn = FakeCdn();
  final MemoryRecordTaskStore store;
  final MemoryRecordFiles files;
  final chat = _Chat();
  late final FakeRemuxer remuxer;
  late final RecordManager manager;
  final history = <String, List<RecordState>>{};

  RecordTask task([String key = 'douyu:9999']) => manager.task(key)!;

  List<RecordState> states([String key = 'douyu:9999']) => history[key] ?? const [];
}

final class _Chat implements RecordChatSource {
  final controllers = <StreamController<RecordChatMessage>>[];

  @override
  Stream<RecordChatMessage> connect(RoomDetail room) {
    final controller = StreamController<RecordChatMessage>();
    controllers.add(controller);
    return controller.stream;
  }
}

void main() {
  test('start → recording → stop: stopped by the user, remuxed, stored without URLs or cookies', () {
    fakeAsync((async) {
      final rig = _Rig();
      unawaited(rig.manager.init());
      async.flushMicrotasks();
      unawaited(rig.manager.add(roomDetail()));
      async.elapse(const Duration(seconds: 12));
      expect(rig.task().state, RecordState.recording);
      expect(rig.states(), containsAllInOrder([RecordState.queued, RecordState.resolving, RecordState.recording]));
      expect(rig.task().session!.bytes, greaterThan(0));
      expect(rig.task().bitsPerSecond, greaterThan(0));
      expect(rig.manager.activeCount, 1);

      unawaited(rig.manager.stop('douyu:9999'));
      async.elapse(const Duration(seconds: 1));
      final task = rig.task();
      expect(task.state, RecordState.stopped);
      expect(task.stopCause, StopCause.user);
      expect(task.userStopped, isTrue);
      expect(rig.states(), containsAllInOrder([RecordState.finalizing, RecordState.stopped]));
      final mp4 = task.session!.outputs.single;
      expect(mp4, endsWith('_001.mp4'));
      expect(rig.files.paths, contains(mp4));
      expect(rig.files.paths.where((path) => path.endsWith('.flv')), isEmpty, reason: 'source deleted after remux');
      expect(rig.manager.activeCount, 0);

      final stored = jsonEncode(rig.store.stored);
      expect(stored, contains('"state":"stopped"'));
      expect(stored, isNot(contains('token')));
      expect(stored, isNot(contains('secret')));
      expect(stored, isNot(contains('cdn.test')));
    });
  });

  test('concurrency: one slot, FIFO, 5 s between starts, slot kept while reconnecting (§11)', () {
    fakeAsync((async) {
      final rig = _Rig(settings: const RecordSettings(maxConcurrent: 1));
      unawaited(rig.manager.init());
      unawaited(rig.manager.add(roomDetail(roomId: '1')));
      unawaited(rig.manager.add(roomDetail(roomId: '2')));
      async.elapse(const Duration(seconds: 10));
      expect(rig.task('douyu:1').state, RecordState.recording);
      expect(rig.task('douyu:2').state, RecordState.queued);

      // A lost connection keeps the slot (REG-RECORD-031).
      rig.rooms.down = true;
      rig.cdn.cutAll();
      async.elapse(const Duration(seconds: 5));
      expect(rig.task('douyu:1').state, RecordState.reconnecting);
      expect(rig.task('douyu:2').state, RecordState.queued);
      rig.rooms.down = false;

      unawaited(rig.manager.stop('douyu:1'));
      async.elapse(const Duration(seconds: 4));
      expect(rig.task('douyu:2').state, isNot(RecordState.queued));
      unawaited(rig.manager.dispose());
      async.elapse(const Duration(seconds: 5));
    });
  });

  test('starts are spaced 5 s apart (§11.3)', () {
    fakeAsync((async) {
      final rig = _Rig();
      unawaited(rig.manager.init());
      unawaited(rig.manager.add(roomDetail(roomId: '1')));
      unawaited(rig.manager.add(roomDetail(roomId: '2')));
      async.elapse(const Duration(seconds: 1));
      expect(rig.task('douyu:1').state, isNot(RecordState.queued));
      expect(rig.task('douyu:2').state, RecordState.queued);
      async.elapse(const Duration(seconds: 5));
      expect(rig.task('douyu:2').state, isNot(RecordState.queued));
      unawaited(rig.manager.dispose());
      async.elapse(const Duration(seconds: 5));
    });
  });

  test('waiting for live: added without start, polled until live, then recorded (§12)', () {
    fakeAsync((async) {
      final rig = _Rig(settings: const RecordSettings(polling: true));
      rig.rooms.live = false;
      unawaited(rig.manager.init());
      unawaited(rig.manager.add(roomDetail(), start: false));
      async.flushMicrotasks();
      expect(rig.task().state, RecordState.waitingLive);
      expect(rig.task().nextCheckAt, isNotNull);
      async.elapse(const Duration(seconds: 61));
      expect(rig.rooms.detailCalls, 2);
      expect(rig.task().state, RecordState.waitingLive);
      rig.rooms.live = true;
      async.elapse(const Duration(seconds: 35));
      expect(rig.task().state, RecordState.recording);
      unawaited(rig.manager.dispose());
      async.elapse(const Duration(seconds: 5));
    });
  });

  test('retries exhausted with polling off fail the task instead of waiting forever (REG-RECORD-033)', () {
    fakeAsync((async) {
      final rig = _Rig(settings: const RecordSettings(maxRetries: 2, retryDelay: Duration(seconds: 5)));
      unawaited(rig.manager.init());
      unawaited(rig.manager.add(roomDetail()));
      async.elapse(const Duration(seconds: 5));
      rig.rooms.down = true;
      rig.cdn.cutAll();
      async.elapse(const Duration(minutes: 2));
      final task = rig.task();
      expect(task.state, RecordState.failed);
      expect(task.failure?.kind, RecordErrorKind.retriesExhausted);
      expect(rig.states(), isNot(contains(RecordState.waitingLive)));
      final calls = rig.rooms.detailCalls;
      async.elapse(const Duration(minutes: 30));
      expect(rig.rooms.detailCalls, calls, reason: 'nothing runs after the failure');
    });
  });

  test('retries exhausted with polling on go back to waiting and keep checking', () {
    fakeAsync((async) {
      final rig = _Rig(settings: const RecordSettings(maxRetries: 1, retryDelay: Duration(seconds: 5), polling: true));
      unawaited(rig.manager.init());
      unawaited(rig.manager.add(roomDetail()));
      async.elapse(const Duration(seconds: 5));
      rig.rooms.down = true;
      rig.cdn.cutAll();
      async.elapse(const Duration(seconds: 30));
      expect(rig.task().state, RecordState.waitingLive);
      rig.rooms.down = false;
      async.elapse(const Duration(seconds: 40));
      expect(rig.task().state, RecordState.recording);
      unawaited(rig.manager.dispose());
      async.elapse(const Duration(seconds: 5));
    });
  });

  test('offline confirmed: waiting with polling on, completed with polling off (§3)', () {
    fakeAsync((async) {
      for (final polling in [true, false]) {
        final rig = _Rig(settings: RecordSettings(polling: polling));
        unawaited(rig.manager.init());
        unawaited(rig.manager.add(roomDetail()));
        async.elapse(const Duration(seconds: 5));
        rig.rooms.live = false;
        rig.cdn.ended = true;
        async.elapse(const Duration(seconds: 10));
        expect(rig.task().state, polling ? RecordState.waitingLive : RecordState.completed);
        expect(rig.task().session!.outputs, hasLength(1));
        unawaited(rig.manager.dispose());
        async.elapse(const Duration(seconds: 5));
      }
    });
  });

  test('a stop while finalising after the room went offline ends stopped, not waiting', () {
    fakeAsync((async) {
      final rig = _Rig(settings: const RecordSettings(polling: true));
      unawaited(rig.manager.init());
      unawaited(rig.manager.add(roomDetail()));
      async.elapse(const Duration(seconds: 5));
      rig.manager.updates.where((task) => task.state == RecordState.finalizing).take(1).listen((_) {
        unawaited(rig.manager.stop('douyu:9999'));
      });
      rig.rooms.live = false;
      rig.cdn.ended = true;
      async.elapse(const Duration(seconds: 10));
      expect(rig.task().state, RecordState.stopped);
      expect(rig.task().stopCause, StopCause.user);
      expect(rig.task().nextCheckAt, isNull);
      final calls = rig.rooms.detailCalls;
      async.elapse(const Duration(minutes: 5));
      expect(rig.rooms.detailCalls, calls);
    });
  });

  test('switching polling off stops waiting tasks; switching it on checks them at once (§12)', () {
    fakeAsync((async) {
      final rig = _Rig(settings: const RecordSettings(polling: true));
      rig.rooms.live = false;
      unawaited(rig.manager.init());
      unawaited(rig.manager.add(roomDetail(), start: false));
      async.flushMicrotasks();
      unawaited(rig.manager.updateSettings(rig.manager.settings.copyWith(polling: false)));
      async.flushMicrotasks();
      expect(rig.task().state, RecordState.stopped);
      expect(rig.task().stopCause, StopCause.pollingOff);
      final calls = rig.rooms.detailCalls;
      async.elapse(const Duration(minutes: 10));
      expect(rig.rooms.detailCalls, calls, reason: 'no timer survives');

      unawaited(rig.manager.updateSettings(rig.manager.settings.copyWith(polling: true)));
      async.elapse(const Duration(milliseconds: 10));
      expect(rig.task().state, RecordState.waitingLive);
      expect(rig.rooms.detailCalls, calls + 1, reason: 'checked at once');
      unawaited(rig.manager.dispose());
      async.elapse(const Duration(seconds: 5));
    });
  });

  test('a late check answer after the user stopped is dropped (REG-RECORD-016)', () {
    fakeAsync((async) {
      final rig = _Rig(settings: const RecordSettings(polling: true));
      rig.rooms.live = false;
      unawaited(rig.manager.init());
      unawaited(rig.manager.add(roomDetail(), start: false));
      async.flushMicrotasks();
      final gate = Completer<void>();
      rig.rooms.detailGate = gate.future;
      unawaited(rig.manager.checkNow('douyu:9999'));
      async.flushMicrotasks();
      unawaited(rig.manager.stop('douyu:9999'));
      async.flushMicrotasks();
      rig.rooms
        ..live = true
        ..detailGate = null;
      gate.complete();
      async.elapse(const Duration(seconds: 10));
      expect(rig.task().state, RecordState.stopped);
      expect(rig.cdn.opened, isEmpty);
    });
  });

  test('user intents run in order: start waits for a running stop (REG-RECORD-017)', () {
    fakeAsync((async) {
      final rig = _Rig();
      unawaited(rig.manager.init());
      unawaited(rig.manager.add(roomDetail()));
      async.elapse(const Duration(seconds: 5));
      final order = <String>[];
      unawaited(rig.manager.stop('douyu:9999').then((_) => order.add('stopped ${rig.task().state.name}')));
      unawaited(rig.manager.start('douyu:9999').then((_) => order.add('started ${rig.task().state.name}')));
      async.elapse(const Duration(seconds: 1));
      expect(order, ['stopped stopped', 'started queued']);
      async.elapse(const Duration(seconds: 10));
      expect(rig.task().state, RecordState.recording);
      expect(rig.task().session!.layout.prefix, isNot(rig.store.stored.isEmpty ? '' : 'x'));
      unawaited(rig.manager.dispose());
      async.elapse(const Duration(seconds: 5));
    });
  });

  test('crash recovery finishes the files at every launch; start waits for it (§14.1, REG-RECORD-035)', () {
    fakeAsync((async) {
      final files = MemoryRecordFiles();
      final layout = SessionLayout.at('/rec', RoomRef('douyu', '9999'), '主播', clock.now());
      const flv = SyntheticFlv();
      files.put('${layout.segment(1)}.part', [for (final packet in flv.connection(0, 5000)) ...packet, 1, 2]);
      final crashed = RecordTask(
        room: RoomRef('douyu', '9999'),
        createdAt: clock.now(),
        state: RecordState.recording,
        session: RecordSessionInfo(layout: layout),
      );
      final rig = _Rig(store: MemoryRecordTaskStore([crashed]), files: files);
      unawaited(rig.manager.init());
      async.flushMicrotasks();
      expect(rig.task().state, RecordState.finalizing);
      var started = false;
      unawaited(rig.manager.start('douyu:9999').then((_) => started = true));
      async.flushMicrotasks();
      expect(started, isFalse, reason: 'the start waits for recovery');
      async.elapse(const Duration(seconds: 1));
      expect(rig.remuxer.inputs.single, layout.segment(1));
      expect(files.paths.where((path) => path.contains(layout.prefix) && path.endsWith('.part')), isEmpty);
      expect(started, isTrue);
      async.elapse(const Duration(seconds: 10));
      expect(rig.task().state, RecordState.recording);
      unawaited(rig.manager.dispose());
      async.elapse(const Duration(seconds: 5));
    });
  });

  test('without resumeOnLaunch a crashed task ends stopped; with it the task records again (§14.2)', () {
    fakeAsync((async) {
      for (final resume in [false, true]) {
        final files = MemoryRecordFiles();
        final crashed = RecordTask(
          room: RoomRef('douyu', '9999'),
          createdAt: clock.now(),
          state: RecordState.reconnecting,
          session: RecordSessionInfo(layout: SessionLayout.at('/rec', RoomRef('douyu', '9999'), 'a', clock.now())),
        );
        final rig = _Rig(
          settings: RecordSettings(resumeOnLaunch: resume),
          store: MemoryRecordTaskStore([crashed]),
          files: files,
        );
        unawaited(rig.manager.init());
        async.elapse(const Duration(seconds: 10));
        if (resume) {
          expect(rig.task().state, RecordState.recording);
        } else {
          expect(rig.task().state, RecordState.stopped);
          expect(rig.task().stopCause, isNull);
          expect(rig.cdn.opened, isEmpty);
        }
        unawaited(rig.manager.dispose());
        async.elapse(const Duration(seconds: 5));
      }
    });
  });

  test('app exit stops tasks for the next launch to resume (§16.2, §14.2)', () {
    fakeAsync((async) {
      final store = MemoryRecordTaskStore();
      final files = MemoryRecordFiles();
      final first = _Rig(store: store, files: files);
      unawaited(first.manager.init());
      unawaited(first.manager.add(roomDetail()));
      async.elapse(const Duration(seconds: 10));
      unawaited(first.manager.stopAll());
      async.elapse(const Duration(seconds: 1));
      expect(first.task().state, RecordState.stopped);
      expect(first.task().stopCause, StopCause.appRestart);
      expect(first.remuxer.inputs, isEmpty, reason: 'no remux on exit');
      expect(files.paths.where((path) => path.endsWith('.flv')), hasLength(1));

      final second = _Rig(store: store, files: files, settings: const RecordSettings(resumeOnLaunch: true));
      unawaited(second.manager.init());
      async.elapse(const Duration(seconds: 10));
      expect(second.remuxer.inputs, hasLength(1), reason: 'the exit left the remux to this launch');
      expect(second.task().state, RecordState.recording);
      unawaited(second.manager.dispose());
      async.elapse(const Duration(seconds: 5));
    });
  });

  test('background time running out fails active tasks with backgroundInterrupted (§16.1)', () {
    fakeAsync((async) {
      final rig = _Rig();
      unawaited(rig.manager.init());
      unawaited(rig.manager.add(roomDetail()));
      async.elapse(const Duration(seconds: 5));
      unawaited(rig.manager.interruptAll());
      async.elapse(const Duration(seconds: 1));
      expect(rig.task().state, RecordState.failed);
      expect(rig.task().failure?.kind, RecordErrorKind.backgroundInterrupted);
    });
  });

  test('a failed remux keeps the source and fails the task; retrying converts it (§10)', () {
    fakeAsync((async) {
      final rig = _Rig();
      rig.remuxer.fail = true;
      unawaited(rig.manager.init());
      unawaited(rig.manager.add(roomDetail()));
      async.elapse(const Duration(seconds: 5));
      unawaited(rig.manager.stop('douyu:9999'));
      async.elapse(const Duration(seconds: 1));
      expect(rig.task().state, RecordState.failed);
      expect(rig.task().failure?.kind, RecordErrorKind.remuxFailed);
      expect(rig.files.paths.where((path) => path.endsWith('.flv')), hasLength(1));
      expect(rig.files.paths.where((path) => path.contains('.mp4')), isEmpty, reason: '.partial removed');

      rig.remuxer.fail = false;
      unawaited(rig.manager.retryRemux('douyu:9999'));
      async.elapse(const Duration(seconds: 1));
      expect(rig.task().failure, isNull);
      expect(rig.task().state, RecordState.completed);
      expect(rig.task().session!.outputs, hasLength(1));
    });
  });

  test('a codec MP4 cannot hold (MPEG-2 on IPTV) keeps the source and is not a failure (§10)', () async {
    // Through the app's isolate remuxer: the flag must survive the isolate.
    final dir = await Directory.systemTemp.createTemp('remux_skip');
    addTearDown(() => dir.delete(recursive: true));
    final input = '${dir.path}${Platform.pathSeparator}a_001.ts';
    await File(input).writeAsBytes(TsLive(videoType: 0x02, durationMs: 4000).bytes(0, 1 << 20));
    final outcome = await remuxFiles(
      files: const IoRecordFiles(),
      remuxer: const IsolateRemuxer(Mp4Remuxer()),
      inputs: [input],
    );
    expect(outcome.failure, isNull);
    expect(outcome.outputs, isEmpty);
    expect(outcome.skipped, [input]);
    expect(outcome.kept, [input]);
    expect(File(input).existsSync(), isTrue);
    expect(dir.listSync().whereType<File>().map((f) => f.path), [input], reason: 'no partial MP4 left behind');
  });

  test('remux progress is reported, never decreasing, 1 only at the end', () async {
    final files = MemoryRecordFiles()
      ..put('/a_001.flv', List.filled(1000, 1))
      ..put('/a_002.flv', List.filled(1000, 2));
    final progress = <double>[];
    final outcome = await remuxFiles(
      files: files,
      remuxer: FakeRemuxer(files),
      inputs: ['/a_001.flv', '/a_002.flv'],
      onProgress: progress.add,
    );
    expect(outcome.outputs, ['/a_001.mp4', '/a_002.mp4']);
    expect(progress.last, 1);
    expect(progress.where((value) => value < 1), everyElement(lessThanOrEqualTo(0.99)));
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThan(progress[i - 1]));
    }
  });

  test('a remux without progress for 60 s fails and keeps the source', () {
    fakeAsync((async) {
      final files = MemoryRecordFiles()..put('/a_001.flv', [1, 2, 3]);
      RemuxOutcome? outcome;
      unawaited(
        remuxFiles(files: files, remuxer: _StuckRemuxer(), inputs: ['/a_001.flv']).then((value) => outcome = value),
      );
      async.elapse(const Duration(seconds: 59));
      expect(outcome, isNull);
      async.elapse(const Duration(seconds: 12));
      expect(outcome?.failure?.kind, RecordErrorKind.remuxFailed);
      expect(outcome?.kept, ['/a_001.flv']);
    });
  });

  test('state writes are coalesced; progress is written at most every 10 s (§13)', () {
    fakeAsync((async) {
      final rig = _Rig();
      unawaited(rig.manager.init());
      unawaited(rig.manager.add(roomDetail()));
      async.elapse(const Duration(seconds: 5));
      final saves = rig.store.saves;
      async.elapse(const Duration(seconds: 60));
      expect(rig.store.saves - saves, inInclusiveRange(5, 7));
      unawaited(rig.manager.dispose());
      async.elapse(const Duration(seconds: 5));
    });
  });

  test('remove stops the task and forgets it; the files stay', () {
    fakeAsync((async) {
      final rig = _Rig();
      unawaited(rig.manager.init());
      unawaited(rig.manager.add(roomDetail()));
      async.elapse(const Duration(seconds: 5));
      unawaited(rig.manager.remove('douyu:9999'));
      async.elapse(const Duration(seconds: 1));
      expect(rig.manager.task('douyu:9999'), isNull);
      expect(rig.store.stored, isEmpty);
      expect(rig.files.paths.where((path) => path.endsWith('.mp4')), hasLength(1));
    });
  });

  test('chat is recorded while the session runs; a dropped chat reconnects after 30 s (§17)', () {
    fakeAsync((async) {
      final rig = _Rig(settings: const RecordSettings(danmaku: true, remuxToMp4: false));
      unawaited(rig.manager.init());
      unawaited(rig.manager.add(roomDetail()));
      async.elapse(const Duration(seconds: 3));
      expect(rig.chat.controllers, hasLength(1));
      rig.chat.controllers.single
        ..add(const RecordChatMessage(text: 'one', userName: 'a'))
        ..addError(const SocketException('chat lost'));
      async.elapse(const Duration(seconds: 29));
      expect(rig.chat.controllers, hasLength(1));
      expect(rig.task().state, RecordState.recording, reason: 'chat never affects the video');
      async.elapse(const Duration(seconds: 2));
      expect(rig.chat.controllers, hasLength(2));
      rig.chat.controllers.last.add(const RecordChatMessage(text: 'two', userName: 'b'));
      async.elapse(const Duration(seconds: 1));
      unawaited(rig.manager.stop('douyu:9999'));
      async.elapse(const Duration(seconds: 1));
      final xml = rig.files.paths.singleWhere((path) => path.endsWith('.xml'));
      final text = utf8.decode(rig.files.bytesOf(xml)!);
      expect(text, contains('>one</d>'));
      expect(text, contains('>two</d>'));
    });
  });

  test('force start: a queued task takes an extra slot at once; the limit still holds for others (§2, §11.1)', () {
    fakeAsync((async) {
      final rig = _Rig(settings: const RecordSettings(maxConcurrent: 1, remuxToMp4: false));
      unawaited(rig.manager.init());
      unawaited(rig.manager.add(roomDetail(roomId: '1')));
      unawaited(rig.manager.add(roomDetail(roomId: '2')));
      async.elapse(const Duration(seconds: 2));
      expect(rig.task('douyu:1').state, isNot(RecordState.queued));
      expect(rig.task('douyu:2').state, RecordState.queued);

      unawaited(rig.manager.forceStart('douyu:2'));
      async.elapse(const Duration(seconds: 2));
      expect(rig.task('douyu:2').state, RecordState.recording, reason: 'no slot, no 5 s spacing');
      expect(rig.task('douyu:1').state, RecordState.recording);

      unawaited(rig.manager.add(roomDetail(roomId: '3')));
      async.elapse(const Duration(seconds: 10));
      expect(rig.task('douyu:3').state, RecordState.queued, reason: 'the forced slot is an extra one');
      unawaited(rig.manager.stop('douyu:2'));
      async.elapse(const Duration(seconds: 10));
      expect(rig.task('douyu:3').state, RecordState.queued, reason: 'the extra slot ends with its session');
      unawaited(rig.manager.stop('douyu:1'));
      async.elapse(const Duration(seconds: 10));
      expect(rig.task('douyu:3').state, isNot(RecordState.queued));
      unawaited(rig.manager.dispose());
      async.elapse(const Duration(seconds: 5));
    });
  });

  test('force start: a waiting task starts now; offline goes back to waiting (§2, §12)', () {
    fakeAsync((async) {
      final rig = _Rig(settings: const RecordSettings(polling: true, maxConcurrent: 1, remuxToMp4: false));
      rig.rooms.live = false;
      unawaited(rig.manager.init());
      unawaited(rig.manager.add(roomDetail(), start: false));
      async.flushMicrotasks();
      expect(rig.task().state, RecordState.waitingLive);

      // Offline: the strict check ends the session and polling resumes.
      unawaited(rig.manager.forceStart('douyu:9999'));
      async.elapse(const Duration(seconds: 2));
      expect(rig.states(), containsAllInOrder([RecordState.queued, RecordState.resolving, RecordState.waitingLive]));
      expect(rig.task().state, RecordState.waitingLive);
      expect(rig.task().nextCheckAt, isNotNull);

      // Live: recorded at once, not at the next check 30 s away.
      rig.rooms.live = true;
      unawaited(rig.manager.forceStart('douyu:9999'));
      async.elapse(const Duration(seconds: 2));
      expect(rig.task().state, RecordState.recording);
      expect(rig.task().nextCheckAt, isNull);
      unawaited(rig.manager.dispose());
      async.elapse(const Duration(seconds: 5));
    });
  });

  test('storage limit: every minute the oldest files go; the recording folder is kept (§15)', () {
    fakeAsync((async) {
      const mb = 1024 * 1024;
      final rig = _Rig(settings: const RecordSettings(storageLimitMegabytes: 1, remuxToMp4: false));
      final old = DateTime.utc(2026);
      rig.files
        ..put('/rec/huya/someone/2026-01-01/a_001.flv', List.filled(2 * mb, 0), modified: old)
        ..put('/rec/huya/someone/2026-01-02/b_001.flv', List.filled(2 * mb, 0), modified: old);
      unawaited(rig.manager.init());
      unawaited(rig.manager.add(roomDetail()));
      async.elapse(const Duration(seconds: 30));
      expect(rig.files.paths, hasLength(greaterThanOrEqualTo(3)), reason: 'nothing deleted before the first check');
      async.elapse(const Duration(seconds: 31));
      expect(rig.files.paths.where((path) => path.startsWith('/rec/huya')), isEmpty);
      expect(rig.files.directories, isNot(contains('/rec/huya')));
      final directory = rig.task().session!.layout.directory;
      expect(rig.files.paths.where((path) => path.startsWith(directory)), isNotEmpty, reason: 'protected');

      // Switched off: no more checks.
      unawaited(rig.manager.updateSettings(rig.manager.settings.copyWith(storageLimitMegabytes: 0)));
      rig.files.put('/rec/kuaishou/x/2026-01-01/c_001.flv', List.filled(2 * mb, 0), modified: old);
      async.elapse(const Duration(minutes: 3));
      expect(rig.files.paths, contains('/rec/kuaishou/x/2026-01-01/c_001.flv'));
      unawaited(rig.manager.dispose());
      async.elapse(const Duration(seconds: 5));
    });
  });

  test('importTasks replaces idle tasks, keeps active ones and waits for monitored rooms (store.md §7.2)', () {
    fakeAsync((async) {
      final rig = _Rig(settings: const RecordSettings(polling: true, remuxToMp4: false));
      unawaited(rig.manager.init());
      unawaited(rig.manager.add(roomDetail(roomId: '1')));
      async.elapse(const Duration(seconds: 3));
      rig.rooms.live = false;
      unawaited(rig.manager.add(roomDetail(roomId: '2'), start: false));
      unawaited(rig.manager.add(roomDetail(roomId: '3'), start: false));
      async.flushMicrotasks();
      unawaited(rig.manager.stop('douyu:3'));
      async.flushMicrotasks();
      expect(rig.task('douyu:2').state, RecordState.waitingLive);

      int? written;
      unawaited(
        rig.manager
            .importTasks([
              RecordTask(
                room: RoomRef('douyu', '2'),
                createdAt: DateTime.utc(2026),
                state: RecordState.stopped,
                stopCause: StopCause.user,
                quality: RecordQuality.smooth,
              ),
              RecordTask(
                room: RoomRef('douyu', '4'),
                createdAt: DateTime.utc(2026),
                state: RecordState.stopped,
                stopCause: StopCause.pollingOff,
                snapshot: const RecordRoomSnapshot(anchorName: '四'),
              ),
              RecordTask(room: RoomRef('douyu', '1'), createdAt: DateTime.utc(2026), state: RecordState.stopped),
            ])
            .then((value) => written = value),
      );
      async.elapse(const Duration(seconds: 1));
      expect(written, 2, reason: 'the recording task is left alone');
      expect(rig.task('douyu:1').state, RecordState.recording);
      expect(rig.manager.task('douyu:3'), isNull, reason: 'not in the backup and idle: removed');
      expect(rig.task('douyu:2').state, RecordState.stopped);
      expect(rig.task('douyu:2').stopCause, StopCause.user);
      expect(rig.task('douyu:2').quality, RecordQuality.smooth);
      expect(rig.task('douyu:4').state, RecordState.waitingLive);
      expect(rig.task('douyu:4').snapshot.anchorName, '四');
      expect(rig.manager.tasks.map((task) => task.key), ['douyu:1', 'douyu:2', 'douyu:4']);
      expect(rig.store.stored.keys, containsAll(['douyu:1', 'douyu:2', 'douyu:4']));
      expect(rig.store.stored.keys, isNot(contains('douyu:3')));
      unawaited(rig.manager.dispose());
      async.elapse(const Duration(seconds: 5));
    });
  });

  test('JsonFileRecordTaskStore round-trips tasks atomically', () async {
    final dir = await Directory.systemTemp.createTemp('live_record_store');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/record_tasks.json';
    final store = JsonFileRecordTaskStore(path);
    final task = RecordTask(
      room: RoomRef('douyu', '9999'),
      createdAt: DateTime.utc(2026, 9, 27),
      state: RecordState.failed,
      quality: RecordQuality.superHd,
      cursor: const RecordCursor(qualityId: '2', lineIndex: 1),
      failure: RecordFailure(RecordErrorKind.http4xx, RecordStage.network, 'https://x.test/a.flv?token=1 HTTP 403'),
      session: RecordSessionInfo(
        layout: SessionLayout.at('/rec', RoomRef('douyu', '9999'), 'a', DateTime.utc(2026, 9, 27)),
        media: const Duration(days: 500),
        bytes: 42,
      ),
    );
    await store.save([task]);
    final loaded = (await JsonFileRecordTaskStore(path).load()).single;
    expect(loaded.key, 'douyu:9999');
    expect(loaded.state, RecordState.failed);
    expect(loaded.quality, RecordQuality.superHd);
    expect(loaded.cursor, const RecordCursor(qualityId: '2', lineIndex: 1));
    expect(loaded.failure?.kind, RecordErrorKind.http4xx);
    expect(loaded.failure?.message, isNot(contains('token')));
    expect(loaded.session?.bytes, 42);
    expect(loaded.session?.media, Duration.zero, reason: 'a duration over a year is damage (REG-RECORD-011)');
    await store.remove('douyu:9999');
    expect(await JsonFileRecordTaskStore(path).load(), isEmpty);
    expect(File('$path.tmp').existsSync(), isFalse);
  });
}

final class _StuckRemuxer implements Remuxer {
  @override
  Future<void> remux(RemuxJob job) => job.cancelled;
}
