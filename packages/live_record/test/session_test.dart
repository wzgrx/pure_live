import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/live_record.dart';
import 'package:live_record/testing.dart';
import 'package:test/test.dart';

import 'support/fake_live.dart';

final class _Rig {
  new({
    RecordSettings settings = const RecordSettings(),
    FakeRooms? rooms,
    FakeCdn? cdn,
    RecordQuality? quality,
    bool? autoReconnect,
  }) : rooms = rooms ?? FakeRooms(),
       cdn = cdn ?? FakeCdn() {
    layout = SessionLayout.at('/rec', RoomRef('douyu', '9999'), '主播', clock.now());
    session = RecordSession(
      room: RoomRef('douyu', '9999'),
      rooms: this.rooms,
      layout: layout,
      files: files,
      settings: settings,
      opener: this.cdn.open,
      quality: quality,
      autoReconnect: autoReconnect,
      onPhase: phases.add,
      onRetry: (failure, delay) => retries.add((failure.kind, delay)),
      onSplice: splices.add,
    );
    unawaited(session.run().then((value) => result = value));
  }

  final FakeRooms rooms;
  final FakeCdn cdn;
  final files = MemoryRecordFiles();
  late final SessionLayout layout;
  late final RecordSession session;
  SessionResult? result;
  final phases = <SessionPhase>[];
  final retries = <(RecordErrorKind, Duration)>[];
  final splices = <SpliceEvent>[];

  FlvFile file(int index) => FlvFile(files.bytesOf(layout.segment(index))!);

  List<Object?> get gaps =>
      (jsonDecode(utf8.decode(files.bytesOf(layout.gaps)!)) as Map<String, Object?>)['gaps']! as List<Object?>;
}

void main() {
  test('a Douyu lease splices through two renewals: one file, one frame step, no gaps (§5.1, §22)', () {
    fakeAsync((async) {
      final rig = _Rig(
        rooms: FakeRooms(leaseSeconds: 300, cutsConnection: true),
        cdn: FakeCdn(cutAfter: const Duration(seconds: 300)),
      );
      async.elapse(const Duration(seconds: 700));
      unawaited(rig.session.stop());
      async.flushMicrotasks();

      final result = rig.result!;
      expect(result.end, SessionEnd.stopped);
      expect(result.segments, hasLength(1));
      expect(rig.splices.whereType<SpliceSwitched>(), hasLength(2));
      expect(rig.session.progress.connections, 1, reason: 'renewals never reach the outer loop');
      final file = rig.file(1);
      expect(FlvFile.maxStep(file.video), 40, reason: 'one frame across both renewals');
      expect(FlvFile.monotonic(file.video), isTrue);
      expect(FlvFile.monotonic(file.audio, strict: true), isTrue);
      expect(file.video.last, greaterThan(695000));
      expect(file.scripts, 1);
      expect(file.videoConfigs, hasLength(1));
      expect(rig.gaps, isEmpty);
      expect(rig.phases, [SessionPhase.resolving, SessionPhase.recording, SessionPhase.finalizing]);
      expect(rig.files.paths.where((path) => path.endsWith('.part')), isEmpty);
    });
  });

  test('an upstream EOF without lease is renewed at once and continues the file; the skipped GOP is a gap', () {
    fakeAsync((async) {
      // Cut mid-GOP: the new connection can only join at the next keyframe.
      final rig = _Rig(cdn: FakeCdn(cutAfter: const Duration(milliseconds: 60500)));
      async.elapse(const Duration(seconds: 150));
      unawaited(rig.session.stop());
      async.flushMicrotasks();

      expect(rig.result!.segments, hasLength(1));
      expect(rig.session.progress.connections, 1);
      expect(rig.splices.whereType<SpliceSwitched>().every((event) => event.oldEnded), isTrue);
      final gaps = rig.gaps.cast<Map<String, Object?>>();
      expect(gaps, isNotEmpty);
      expect(gaps.every((gap) => gap['reason'] == 'splice'), isTrue);
      expect(gaps.every((gap) => (gap['missingMs']! as int) <= 1000), isTrue, reason: 'at most one GOP');
      expect(gaps.first['missingMs'], 161000 - 160480 - 40, reason: 'last frame 160.48 s, next keyframe 161 s');
      expect(FlvFile.monotonic(rig.file(1).video), isTrue);
    });
  });

  test('the room going offline ends the session after a strict check (§3, REG-RECORD-003)', () {
    fakeAsync((async) {
      final rig = _Rig();
      async.elapse(const Duration(seconds: 30));
      rig.rooms.live = false;
      rig.cdn.ended = true;
      async.elapse(const Duration(seconds: 30));

      expect(rig.result?.end, SessionEnd.offline);
      expect(rig.phases, containsAllInOrder([SessionPhase.recording, SessionPhase.reconnecting]));
      expect(rig.retries.first, (RecordErrorKind.upstreamEof, const Duration(seconds: 2)));
      expect(rig.result!.segments.single.closed, isTrue);
    });
  });

  test('network loss backs off regularly and gives up after maxRetries, never a 2 s loop (REG-RECORD-034)', () {
    fakeAsync((async) {
      final rig = _Rig(settings: const RecordSettings(maxRetries: 3));
      async.elapse(const Duration(seconds: 20));
      final before = rig.rooms.detailCalls;
      rig.rooms.down = true;
      rig.cdn.down = true;
      rig.cdn.cutAll();
      async.elapse(const Duration(minutes: 10));

      expect(rig.result?.end, SessionEnd.exhausted);
      expect(rig.result?.failure?.kind, RecordErrorKind.network);
      final checks = rig.rooms.detailTimes.skip(before).toList();
      expect(checks, hasLength(4), reason: 'one fast reconnect, then three regular retries');
      for (var i = 2; i < checks.length; i++) {
        expect(checks[i].difference(checks[i - 1]), const Duration(seconds: 30));
      }
      expect(rig.retries.map((retry) => retry.$1), [
        RecordErrorKind.upstreamEof,
        RecordErrorKind.network,
        RecordErrorKind.network,
        RecordErrorKind.network,
      ]);
    });
  });

  test('4xx: renew the same line, then the next line, then back off; an old signature is never retried (§11.7)', () {
    fakeAsync((async) {
      final cdn = FakeCdn()..statusAll = 403;
      final rig = _Rig(cdn: cdn);
      async.elapse(const Duration(seconds: 1));
      expect(cdn.opened, hasLength(3));
      expect(cdn.opened.toSet(), hasLength(3), reason: 'a fresh signature every time');
      expect(cdn.opened[0].host, 'hw.cdn.test');
      expect(cdn.opened[1].host, 'hw.cdn.test', reason: 'first 4xx renews the same line');
      expect(cdn.opened[2].host, 'ws.cdn.test', reason: 'second 4xx moves to the next line');
      expect(rig.retries.single, (RecordErrorKind.http4xx, const Duration(seconds: 30)));
      cdn.statusAll = null;
      async.elapse(const Duration(seconds: 40));
      expect(rig.phases.last, SessionPhase.recording);
      unawaited(rig.session.stop());
      async.flushMicrotasks();
      expect(rig.result?.end, SessionEnd.stopped);
    });
  });

  test('5xx: the same URL after 1, 2 and 4 s, then a fresh resolve after regular backoff (§5.4)', () {
    fakeAsync((async) {
      final cdn = FakeCdn()..statusAll = 502;
      final rig = _Rig(cdn: cdn);
      async.elapse(const Duration(seconds: 8));
      expect(cdn.opened, hasLength(4));
      expect(cdn.opened.toSet(), hasLength(1), reason: 'same URL');
      expect(rig.retries.map((retry) => retry.$2.inSeconds), [1, 2, 4, 30]);
      cdn.statusAll = null;
      async.elapse(const Duration(seconds: 30));
      expect(cdn.opened.last, isNot(cdn.opened.first));
      expect(rig.phases.last, SessionPhase.recording);
      unawaited(rig.session.stop());
      async.flushMicrotasks();
    });
  });

  test('every line failing is allLinesFailed with regular backoff, bounded (§4.3)', () {
    fakeAsync((async) {
      final cdn = FakeCdn()..down = true;
      final rig = _Rig(settings: const RecordSettings(maxRetries: 2), cdn: cdn);
      async.elapse(const Duration(minutes: 5));
      expect(rig.result?.end, SessionEnd.exhausted);
      expect(rig.result?.failure?.kind, RecordErrorKind.allLinesFailed);
      expect(rig.retries.map((retry) => retry.$1), everyElement(RecordErrorKind.allLinesFailed));
      expect(cdn.opened.map((url) => url.host).take(4), ['hw.cdn.test', 'ws.cdn.test', 'hw.cdn.test', 'ws.cdn.test']);
    });
  });

  test('a user stop closes and renames the files; nothing is left as .part', () {
    fakeAsync((async) {
      final rig = _Rig();
      async.elapse(const Duration(seconds: 12));
      expect(rig.files.paths.where((path) => path.endsWith('.flv.part')), hasLength(1));
      unawaited(rig.session.stop());
      async.flushMicrotasks();
      expect(rig.result?.end, SessionEnd.stopped);
      expect(rig.files.paths.where((path) => path.endsWith('.part')), isEmpty);
      expect(rig.files.openSinks, isEmpty);
      expect(rig.cdn.connections.single.cancelled, isTrue, reason: 'upstream dropped after the writer closed');
      final progress = rig.session.progress;
      expect(progress.media.inSeconds, inInclusiveRange(10, 12));
      expect(progress.bytes, greaterThan(0));
    });
  });

  test('a stop during a slow room check ends at once', () {
    fakeAsync((async) {
      final rooms = FakeRooms()..detailGate = Completer<void>().future;
      final rig = _Rig(rooms: rooms);
      async.elapse(const Duration(seconds: 1));
      unawaited(rig.session.stop());
      async.flushMicrotasks();
      expect(rig.result?.end, SessionEnd.stopped);
      expect(rig.result?.segments, isEmpty);
      expect(rig.cdn.opened, isEmpty);
    });
  });

  test('a full disk fails the session with its typed kind and drops the upstream', () {
    fakeAsync((async) {
      final rig = _Rig();
      async.elapse(const Duration(seconds: 5));
      rig.files.writeError = const FileSystemException('write', '/rec', OSError('No space left on device', 28));
      async.elapse(const Duration(seconds: 2));
      rig.files.writeError = null;
      async.elapse(const Duration(seconds: 1));
      expect(rig.result?.end, SessionEnd.failed);
      expect(rig.result?.failure?.kind, RecordErrorKind.diskFull);
      expect(rig.cdn.connections.single.cancelled, isTrue);
    });
  });

  test('without automatic reconnection an EOF ends the session (§11.6)', () {
    fakeAsync((async) {
      final rig = _Rig(autoReconnect: false, rooms: FakeRooms(lines: const ['hw']));
      async.elapse(const Duration(seconds: 10));
      rig.cdn
        ..ended = true
        ..cutAll();
      async.elapse(const Duration(seconds: 20));
      expect(rig.result?.end, SessionEnd.ended);
    });
  });

  test('the preferred quality is requested and only that quality is signed (§4.2, §4.3)', () {
    fakeAsync((async) {
      final rig = _Rig(quality: RecordQuality.superHd);
      async.elapse(const Duration(seconds: 3));
      expect(rig.cdn.opened.single.path, '/live/2.flv');
      expect(rig.rooms.streamCalls, 2, reason: 'one to learn the qualities, one for the preferred');
      expect(rig.session.progress.quality, lowQuality);
      unawaited(rig.session.stop());
      async.flushMicrotasks();
      expect(rig.result?.cursor, const RecordCursor(qualityId: '2', lineIndex: 0));
    });
  });

  test('HLS-only lines are unsupported (HLS recording is not built)', () {
    fakeAsync((async) {
      final rooms = FakeRooms()..formats.addAll({'hw': StreamFormat.hls, 'ws': StreamFormat.hls});
      final rig = _Rig(rooms: rooms);
      async.elapse(const Duration(seconds: 1));
      expect(rig.result?.end, SessionEnd.failed);
      expect(rig.result?.failure?.kind, RecordErrorKind.unsupportedProtocol);
    });
  });

  test('an FLV line is used when the set mixes FLV and HLS', () {
    fakeAsync((async) {
      final rooms = FakeRooms()..formats['hw'] = StreamFormat.hls;
      final rig = _Rig(rooms: rooms);
      async.elapse(const Duration(seconds: 2));
      expect(rig.cdn.opened.single.host, 'ws.cdn.test');
      unawaited(rig.session.stop());
      async.flushMicrotasks();
    });
  });

  test('a lease that does not cut the connection is only prefetched and used at EOF (§5.2, REG-RECORD-001)', () {
    fakeAsync((async) {
      final rooms = FakeRooms(leaseSeconds: 120);
      final cdn = FakeCdn(cutAfter: const Duration(seconds: 200));
      final rig = _Rig(rooms: rooms, cdn: cdn);
      async.elapse(const Duration(seconds: 100));
      expect(cdn.connections, hasLength(1), reason: 'a healthy connection is never replaced');
      final afterPrefetch = rooms.streamCalls;
      expect(afterPrefetch, 2, reason: 'first resolve plus one prefetch 5 s before refreshAt');
      async.elapse(const Duration(seconds: 105));
      expect(cdn.connections, hasLength(2), reason: 'the EOF switched to the prefetched URL');
      expect(rig.splices.whereType<SpliceSwitched>().single.oldEnded, isTrue);
      unawaited(rig.session.stop());
      async.flushMicrotasks();
      expect(rig.result!.segments, hasLength(1));
    });
  });

  test('chat is written next to the segment on the file timeline (§17)', () {
    fakeAsync((async) {
      final rig = _Rig(settings: const RecordSettings(danmaku: true));
      async.elapse(const Duration(seconds: 3));
      rig.session
        ..addChat(RecordChatMessage(id: '1', userId: 'u1', userName: 'A&B', text: '<hi>', sentAt: clock.now()))
        ..addChat(const RecordChatMessage(id: '1', userName: 'dup', text: 'again'))
        ..addChat(const RecordChatMessage(id: '2', userName: 'blank', text: '   '));
      async.elapse(const Duration(seconds: 1));
      unawaited(rig.session.stop());
      async.flushMicrotasks();
      final xml = utf8.decode(rig.files.bytesOf(rig.layout.segment(1, extension: 'xml'))!);
      expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(xml.trimRight(), endsWith('</i>'));
      expect(RegExp('<d ').allMatches(xml), hasLength(1), reason: 'duplicates and blank texts are skipped');
      expect(xml, contains('user="A&amp;B">&lt;hi&gt;</d>'));
      final time = double.parse(RegExp('p="([0-9.]+),').firstMatch(xml)!.group(1)!);
      expect(time, inInclusiveRange(1.0, 3.5));
      expect(xml, contains(',${crc32(utf8.encode('u1')).toRadixString(16)},0"'));
    });
  });
}
