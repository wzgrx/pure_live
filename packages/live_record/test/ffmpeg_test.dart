import 'dart:io';

import 'package:live_record/live_record.dart';
import 'package:test/test.dart';

void main() {
  List<String> record({String url = 'https://cdn.example/live.flv?sign=a b', Map<String, String> headers = const {}}) =>
      FfmpegCommand.record(
        url: url,
        outputDir: '/rec dir',
        filePrefix: '20261001_100000_000',
        segmentTime: 300,
        preferBestStream: true,
        rwTimeout: 15,
        threadQueueSize: 2048,
        headers: headers,
      );

  test('capture passes the URL, headers and paths as exact arguments', () {
    final arguments = record(
      headers: {'User-Agent': 'UA', 'Referer': 'https://r.example/\r\nX-Bad: 1', 'bad name': 'x'},
    );
    expect(arguments, containsAllInOrder(['-user_agent', 'UA', '-headers']));
    expect(arguments[arguments.indexOf('-headers') + 1], 'referer: https://r.example/ X-Bad: 1\r\n');
    expect(arguments[arguments.indexOf('-i') + 1], 'https://cdn.example/live.flv?sign=a b');
    expect(arguments.last, '/rec dir/20261001_100000_000_%06d.clock-v1.ts');
    expect(arguments[arguments.indexOf('-segment_list') + 1], '/rec dir/20261001_100000_000.clock-v1.csv');
    expect(
      arguments,
      containsAllInOrder([
        '-segment_format_options',
        'flush_packets=1:avoid_negative_ts=disabled:max_delay=0:output_ts_offset=1.4',
      ]),
    );
    expect(arguments, containsAllInOrder(['-reconnect_on_http_error', '5xx']));
    expect(arguments, containsAllInOrder(['-map', '0:v:0?', '-map', '0:a:0?']));
  });

  test('protocol options follow the scheme and local files keep their timeline', () {
    expect(record(url: 'rtsp://h/x'), containsAllInOrder(['-rtsp_transport', 'tcp']));
    expect(record(url: 'udp://h:1'), contains('-overrun_nonfatal'));
    final file = record(url: 'file:///a.ts');
    expect(file, isNot(contains('-rw_timeout')));
    expect(file, isNot(contains('-dts_delta_threshold')));
    final https = FfmpegCommand.record(
      url: 'https://h/x.flv',
      outputDir: '/o',
      filePrefix: 'p',
      segmentTime: 1,
      preferBestStream: false,
      rwTimeout: 15,
      threadQueueSize: 1,
      caFile: '/ca.pem',
      proxyUrl: 'http://127.0.0.1:7890',
    );
    expect(https, containsAllInOrder(['-http_proxy', 'http://127.0.0.1:7890', '-ca_file', '/ca.pem', '-i']));
    expect(https, containsAllInOrder(['-thread_queue_size', '64', '-segment_time', '10']));
  });

  test('failures are classified with 3.x markers and retry rules', () {
    expect(classifyFfmpegFailure('No space left on device').retryable, isFalse);
    expect(classifyFfmpegFailure('Server returned 403 Forbidden').kind, FfmpegFailureKind.httpAccess);
    expect(classifyFfmpegFailure('Connection reset by peer').kind, FfmpegFailureKind.transport);
    expect(classifyFfmpegFailure('Permission denied').kind, FfmpegFailureKind.outputPath);
    expect(classifyFfmpegFailure('Unrecognized option foo').retryable, isFalse);
    expect(classifyFfmpegFailure('Invalid argument').kind, FfmpegFailureKind.native);
    expect(FfmpegMediaIntegrity.hasPacketError('Packet corrupt (stream = 0'), isTrue);
    expect(FfmpegMediaIntegrity.hasPacketError('Input/output error'), isFalse);
  });

  test('a sentinel FFmpeg time falls back to the wall clock', () {
    expect(normalizeLiveRecordedSeconds(rawMilliseconds: 2147483647000, wallSeconds: 12), 12);
    expect(normalizeLiveRecordedSeconds(rawMilliseconds: 20000, wallSeconds: 12), 20);
    expect(normalizeLiveRecordedSeconds(rawMilliseconds: -5, wallSeconds: 12), 0);
  });

  test('the clock journal gives exact durations and fails closed', () {
    final clock = SegmentClock.parse(
      'p_000000.clock-v1.ts,0.000000,4.100000\np_000001.clock-v1.ts,4.000000,8.000000\n',
      prefix: 'p',
      segments: ['/r/p_000000.clock-v1.ts', '/r/p_000001.clock-v1.ts'],
    );
    expect(clock.toConcatManifest(), contains('duration 4.000000'));
    expect(clock.toConcatManifest(), contains('inpoint 0'));
    for (final bad in [
      'p_000000.clock-v1.ts,0.000000,4.000000',
      'p_000000.clock-v1.ts,1.000000,4.000000\n',
      'q_000000.clock-v1.ts,0.000000,4.000000\n',
    ]) {
      expect(() => SegmentClock.parse(bad, prefix: 'p', segments: ['/r/p_000000.clock-v1.ts']), throwsFormatException);
    }
  });

  test('an attempt joins only its own segments; legacy files only on recovery', () {
    final files = [File('/r/a_000000.clock-v1.ts'), File('/r/b_000000.clock-v1.ts'), File('/r/20260101-000.ts')];
    expect(selectAttemptSegments(files, filePrefix: 'a').single.path, '/r/a_000000.clock-v1.ts');
    expect(selectAttemptSegments(files, filePrefix: 'c'), isEmpty);
    expect(selectAttemptSegments(files, filePrefix: 'c', allowLegacy: true).single.path, '/r/20260101-000.ts');
  });

  test('a reserved output refuses a second writer and existing files', () async {
    final directory = Directory.systemTemp.createTempSync('reserve');
    addTearDown(() => directory.deleteSync(recursive: true));
    final first = await SegmentReservation.acquire(directory.path, 'p');
    await expectLater(SegmentReservation.acquire(directory.path, 'p'), throwsStateError);
    first.release();
    File('${directory.path}/p_000000.clock-v1.ts').writeAsStringSync('x');
    await expectLater(SegmentReservation.acquire(directory.path, 'p'), throwsA(isA<FileSystemException>()));
  });

  test('reconnect, polling and lease timing follow 3.x; a live EOF gets twice the retries (upstream 2b9ffc7a3)', () {
    expect(
      RecordPolicy.reconnectDelay(
        failureCount: 3,
        configuredBaseSeconds: 30,
        configuredMaximumSeconds: 300,
        enableBackoff: true,
        unexpectedEof: true,
      ),
      const Duration(seconds: 15),
    );
    expect(
      RecordPolicy.pollingDelay(failureCount: 30, baseSeconds: 30, maximumSeconds: 300, enableBackoff: true),
      const Duration(seconds: 300),
    );
    expect(
      RecordPolicy.shouldEnterPollingAfterRetryLimit(retryCount: 9, maximumRetries: 5, unexpectedEof: true),
      isFalse,
    );
    expect(
      RecordPolicy.shouldEnterPollingAfterRetryLimit(retryCount: 10, maximumRetries: 5, unexpectedEof: true),
      isTrue,
    );
    expect(
      RecordPolicy.shouldEnterPollingAfterRetryLimit(retryCount: 5, maximumRetries: 5, unexpectedEof: false),
      isTrue,
    );
    expect(
      RecordPolicy.shouldEnterPollingAfterRetryLimit(retryCount: 4, maximumRetries: 5, unexpectedEof: false),
      isFalse,
    );
    final now = DateTime.utc(2026, 10, 2);
    expect(
      RecordPolicy.leasePrefetchDelay(now: now, refreshAt: now.add(const Duration(seconds: 65))),
      const Duration(minutes: 1),
    );
    expect(RecordPolicy.leaseMaintenanceDelay(now: now, refreshAt: now), const Duration(seconds: 30));
    expect(RecordMerger.mergeTimeout(inputBytes: 0, recordedSeconds: 0), const Duration(seconds: 30));
  });
}
