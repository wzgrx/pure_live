// Opt-in native, loopback-only reproduction of short HLS windows and slow
// whole-fragment delivery. No real platform, device, or user preferences.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/common/services/settings/log_controller.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_command_builder.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_manager.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';
import 'package:pure_live/recorder/services/recorder_proxy_routing.dart';

typedef _Scenario = ({String name, int budget, int bodyMs, int headerMs, int runSeconds});

void main() {
  test('whole-media accounting excludes empty HTTP failures and unfinished bodies', () {
    final traces = <Map<String, Object?>>[
      {'upstreamStatus': 200, 'bodyCompleteMs': 12000},
      {'upstreamStatus': 206, 'bodyCompleteMs': 12000},
      {'upstreamStatus': 410, 'bodyCompleteMs': 1},
      {'upstreamStatus': 503, 'bodyCompleteMs': 1},
      {'upstreamStatus': 206, 'bodyCompleteMs': null},
    ];
    expect(_completedMedia(traces), traces.take(2));
  });
  test(
    'rolling CMAF separates read budget from sustained delivery deficit',
    () async {
      final fixture = Directory(Platform.environment['PURELIVE_ROLLING_HLS_FIXTURE']!);
      final root = await Directory(
        p.join(
          Platform.environment['PURELIVE_RECORDING_PROBE_OUTPUT']!,
          'rolling-${DateTime.now().microsecondsSinceEpoch}',
        ),
      ).create(recursive: true);
      Hive.init((await Directory(p.join(root.path, 'hive')).create()).path);
      await HivePrefUtil.init();
      Get.testMode = true;
      Get.put(LogController());
      configureRecorderProxyRouting((_) => 'DIRECT');
      final reports = <Map<String, Object?>>[];
      try {
        await HttpOverrides.runWithHttpOverrides(() async {
          for (final config in <_Scenario>[
            (name: 'healthy-10', budget: 10, bodyMs: 0, headerMs: 0, runSeconds: 12),
            (name: 'continuous-body-10', budget: 10, bodyMs: 12000, headerMs: 0, runSeconds: 34),
            (name: 'continuous-body-15', budget: 15, bodyMs: 12000, headerMs: 0, runSeconds: 34),
            (name: 'delayed-headers-15', budget: 15, bodyMs: 0, headerMs: 12000, runSeconds: 34),
          ]) {
            reports.add(await _capture(config, fixture, root));
          }
        }, _RealNetwork());
        final baseline = reports.first;
        expect(baseline['started'], true);
        expect(baseline['outputBytes'] as int, greaterThan(0));
        expect((baseline['inspection'] as Map)['exitCode'], 0);
        for (final report in reports.skip(1)) {
          expect(report['completedUpstreamVideoRequests'] as int, greaterThanOrEqualTo(1));
          expect(report['windowDurationSeconds'], 6);
          expect(report['minimumWholeBodyMs'] as int, greaterThanOrEqualTo(12000));
        }
        // The 10s local read budget expires before the continuously arriving
        // upstream body is published; 15s permits that same 12s transfer.
        expect(reports[1]['refreshBeforeFirstVideoComplete'], true);
        expect(reports[2]['refreshBeforeFirstVideoComplete'], false);
        expect(reports[3]['refreshBeforeFirstVideoComplete'], false);
        expect(
          reports[2]['receivedVideoSequenceGaps'],
          true,
          reason: 'A longer local budget does not restore expired intermediate media.',
        );
      } finally {
        await File(p.join(root.path, 'summary.json'))
            .writeAsString(const JsonEncoder.withIndent('  ').convert(reports));
        // ignore: avoid_print
        print(jsonEncode(reports));
        configureRecorderProxyRouting(null);
        Get.reset();
        await Hive.close();
      }
    },
    skip: Platform.environment['PURELIVE_ROLLING_HLS_PROBE'] != '1',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<Map<String, Object?>> _capture(_Scenario config, Directory fixture, Directory root) async {
  final output = await Directory(p.join(root.path, config.name)).create();
  final origin = await _RollingOrigin.start(fixture, config);
  final native = FFmpegManager.to;
  final diagnostics = HlsRelayDiagnostics();
  final taskId = 'rolling_${config.name}';
  final events = <Map<String, Object?>>[];
  final subscription = native.stream.listen((event) {
    if (event.taskId == taskId && events.length < 512) {
      events.add({
        'type': event.type.name,
        'atMs': diagnostics.elapsedMilliseconds,
        'code': event.data['code'],
        'manualStop': event.data['manualStop'],
      });
    }
  });
  Future<void>? execution;
  FFmpegHlsInputRelay? relay;
  final report = <String, Object?>{
    'case': config.name,
    'rwTimeout': config.budget,
    'bodyDelayMs': config.bodyMs,
    'headerDelayMs': config.headerMs,
    'windowDurationSeconds': 6,
  };
  try {
    final arguments = FFmpegCommandBuilder.buildRecordArguments(
      url: origin.input.toString(),
      outputDir: output.path,
      segmentTime: 86400,
      preferBestStream: true,
      rwTimeout: config.budget,
      threadQueueSize: 512,
      filePrefix: 'capture',
    );
    execution = native.start(taskId: taskId, arguments: arguments, liveRecording: true, hlsDiagnostics: diagnostics);
    // Fixed controlled exposure, not a claim of healthy live coverage.
    await Future<void>.delayed(Duration(seconds: config.runSeconds));
    relay = native.getSession(taskId)?.inputRelay;
    report['stopRequestedMs'] = diagnostics.elapsedMilliseconds;
    if (native.isRunning(taskId)) await native.stop(taskId);
    await execution.timeout(const Duration(seconds: 20));
    await relay?.close();
    report['stoppedMs'] = diagnostics.elapsedMilliseconds;
    report['started'] = events.any((event) => event['type'] == 'started');
    report['events'] = events;
    final snapshot = diagnostics.snapshot();
    final traces = (snapshot['requests'] as List).cast<Map<String, Object?>>();
    report['requestCount'] = traces.length;
    report['omittedRequests'] = snapshot['omittedRequests'];
    final master = traces.firstWhere((trace) => (trace['manifest'] as Map?)?['kind'] == 'master')['manifest'] as Map;
    final videoId = (master['children'] as List).singleWhere((child) => child['role'] == 'variant')['resourceId'];
    final videoPlaylists = traces
        .where((trace) => trace['resourceId'] == videoId && trace['manifestSource'] == 'upstream')
        .toList();
    final segmentIds = <String>{};
    final sequenceById = <String, int>{};
    for (final playlist in videoPlaylists) {
      for (final segment in ((playlist['manifest'] as Map)['segments'] as List)) {
        final id = segment['resourceId'] as String;
        segmentIds.add(id);
        sequenceById[id] = segment['sequence'] as int;
      }
    }
    final videoRequests = traces.where((trace) => segmentIds.contains(trace['resourceId'])).toList();
    final complete = _completedMedia(videoRequests);
    report['videoSequencesRequested'] = [for (final trace in videoRequests) sequenceById[trace['resourceId']]];
    report['completedUpstreamVideoRequests'] = complete.length;
    final receivedSequences = [for (final trace in complete) sequenceById[trace['resourceId']]!];
    report['completedUpstreamVideoSequences'] = receivedSequences;
    report['receivedVideoSequenceGaps'] = false;
    for (var i = 1; i < receivedSequences.length; i++) {
      if (receivedSequences[i] > receivedSequences[i - 1] + 1) report['receivedVideoSequenceGaps'] = true;
    }
    if (complete.isNotEmpty) {
      final durations = complete.map((trace) => (trace['bodyCompleteMs'] as int) - (trace['startedMs'] as int)).toList()
        ..sort();
      report['minimumWholeBodyMs'] = durations.first;
      final first = complete.first;
      report['firstVideoRequestMs'] = first['startedMs'];
      report['firstVideoBodyMs'] = first['firstBodyMs'];
      report['firstVideoBodyCompleteMs'] = first['bodyCompleteMs'];
      report['firstVideoDeliveryMs'] = first['deliveredMs'];
      report['refreshBeforeFirstVideoComplete'] = videoPlaylists.any(
        (trace) =>
            (trace['startedMs'] as int) > (first['startedMs'] as int) &&
            (trace['startedMs'] as int) < (first['bodyCompleteMs'] as int),
      );
    }
    final files = await output
        .list()
        .where((file) => file is File && p.extension(file.path) == '.ts')
        .cast<File>()
        .toList();
    var bytes = 0;
    for (final file in files) {
      bytes += await file.length();
    }
    report['outputBytes'] = bytes;
    report['outputFiles'] = files.length;
    if (bytes > 0) {
      report['inspection'] = await _inspect(files.first, output);
    }
    await File(p.join(output.path, 'hls-timeline.json')).writeAsString(jsonEncode(snapshot));
    expect(snapshot['omittedRequests'], 0);
    expect(native.isRunning(taskId), false);
    // This opt-in native test is under tool/probes rather than test/.
    // ignore: invalid_use_of_visible_for_testing_member
    expect(relay?.stagingBodyCount ?? 0, 0);
  } finally {
    relay ??= native.getSession(taskId)?.inputRelay;
    try {
      if (native.isRunning(taskId)) await native.stop(taskId);
      await execution?.timeout(const Duration(seconds: 20));
    } finally {
      await relay?.close();
      await subscription.cancel();
      await origin.close();
      await File(p.join(output.path, 'hls-timeline.json')).writeAsString(jsonEncode(diagnostics.snapshot()));
      await File(p.join(output.path, 'origin.json')).writeAsString(jsonEncode(origin.requests));
      await File(p.join(output.path, 'result.json')).writeAsString(jsonEncode(report));
    }
  }
  return report;
}

typedef _Segment = ({String path, int index, double start, double duration});

List<Map<String, Object?>> _completedMedia(List<Map<String, Object?>> requests) => requests
    .where((trace) => const {200, 206}.contains(trace['upstreamStatus']) && trace['bodyCompleteMs'] != null)
    .toList();

class _RollingOrigin {
  _RollingOrigin(this.server, this.files, this.playlists, this.config);
  final HttpServer server;
  final Map<String, File> files;
  final Map<String, List<_Segment>> playlists;
  final _Scenario config;
  final clock = Stopwatch();
  final ended = Completer<void>();
  final requests = <Map<String, Object?>>[];
  final handlers = <Future<void>>{};
  late StreamSubscription<HttpRequest> subscription;
  Uri get input => Uri.parse('http://127.0.0.1:${server.port}/master.m3u8');
  double get edge => 6.1 + clock.elapsedMilliseconds / 1000;

  static Future<_RollingOrigin> start(Directory fixture, _Scenario config) async {
    final files = <String, File>{};
    await for (final file in fixture.list(recursive: true, followLinks: false)) {
      if (file is File) files['/${p.relative(file.path, from: fixture.path).replaceAll('\\', '/')}'] = file;
    }
    final playlists = <String, List<_Segment>>{};
    for (final variant in [0, 1]) {
      final key = '/variant_$variant/index.m3u8';
      final lines = const LineSplitter().convert(await files[key]!.readAsString()).toList();
      final segments = <_Segment>[];
      double start = 0;
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].startsWith('#EXTINF:')) continue;
        final duration = double.parse(lines[i].substring(8).split(',').first);
        segments.add((
          path: '/variant_$variant/${lines[++i]}',
          index: segments.length,
          start: start,
          duration: duration,
        ));
        start += duration;
      }
      expect(start, greaterThanOrEqualTo(59));
      playlists[key] = segments;
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final origin = _RollingOrigin(server, files, playlists, config);
    origin.subscription = server.listen((request) {
      if (!origin.clock.isRunning) origin.clock.start();
      late Future<void> work;
      work = origin.serve(request).whenComplete(() => origin.handlers.remove(work));
      origin.handlers.add(work);
    });
    return origin;
  }

  List<_Segment> window(List<_Segment> segments) {
    final now = edge;
    return segments
        .where((segment) => segment.start + segment.duration <= now && segment.start + segment.duration > now - 6)
        .toList();
  }

  Future<void> delay(int milliseconds) async {
    final elapsed = Completer<void>();
    final timer = Timer(Duration(milliseconds: milliseconds), elapsed.complete);
    try {
      await Future.any([elapsed.future, ended.future]);
    } finally {
      timer.cancel();
    }
    if (ended.isCompleted) throw const HttpException('Fixture stopped');
  }

  Future<void> serve(HttpRequest request) async {
    final row = <String, Object?>{'path': request.uri.path, 'requestMs': clock.elapsedMilliseconds};
    if (requests.length < 512) requests.add(row);
    try {
      final file = files[request.uri.path];
      final playlist = playlists[request.uri.path];
      if (file == null) {
        request.response.statusCode = 404;
      } else if (playlist != null) {
        final current = window(playlist);
        row['sequence'] = current.first.index;
        final variant = request.uri.path.contains('variant_0') ? 0 : 1;
        final content = StringBuffer(
          '#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:2\n'
          '#EXT-X-MEDIA-SEQUENCE:${current.first.index}\n#EXT-X-MAP:URI="init_$variant.mp4"\n',
        );
        for (final segment in current) {
          final pdt = DateTime.utc(2026, 9, 9).add(Duration(microseconds: (segment.start * 1000000).round()));
          content.write(
            '#EXT-X-PROGRAM-DATE-TIME:${pdt.toIso8601String()}\n#EXTINF:${segment.duration},\n${p.basename(segment.path)}\n',
          );
        }
        request.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
        request.response.write(content);
      } else {
        final isVideo = request.uri.path.startsWith('/variant_0/') && request.uri.path.endsWith('.m4s');
        if (request.uri.path.endsWith('.m4s')) {
          final key = request.uri.path.startsWith('/variant_0/') ? '/variant_0/index.m3u8' : '/variant_1/index.m3u8';
          if (!window(playlists[key]!).any((segment) => segment.path == request.uri.path)) {
            row['expiredAtRequest'] = true;
            request.response.statusCode = 410;
            await request.response.close();
            return;
          }
        }
        final bytes = await file.readAsBytes();
        if (isVideo && config.headerMs > 0) await delay(config.headerMs);
        request.response.contentLength = bytes.length;
        request.response.bufferOutput = false;
        if (isVideo && config.bodyMs > 0) {
          for (var part = 0; part < 13; part++) {
            if (part > 0) await delay(config.bodyMs ~/ 12);
            request.response.add(bytes.sublist(part * bytes.length ~/ 13, (part + 1) * bytes.length ~/ 13));
            await request.response.flush();
            row['firstBodyMs'] ??= clock.elapsedMilliseconds;
          }
        } else {
          request.response.add(bytes);
          row['firstBodyMs'] = clock.elapsedMilliseconds;
        }
        row['bytes'] = bytes.length;
      }
      await request.response.close();
      row['closedMs'] = clock.elapsedMilliseconds;
    } on Object {
      row['connectionEnded'] = true;
      try {
        await request.response.close();
      } on Object {
        /* Owned reader ended. */
      }
    }
  }

  Future<void> close() async {
    if (!ended.isCompleted) ended.complete();
    await server.close(force: true);
    await subscription.cancel();
    await Future.wait(handlers.toList());
    clock.stop();
  }
}

class _RealNetwork extends HttpOverrides {}

Future<Map<String, Object?>> _inspect(File input, Directory output) async {
  final process = await Process.start(Platform.environment['PURELIVE_FFPROBE']!, [
    '-v',
    'error',
    '-show_packets',
    '-show_streams',
    '-show_entries',
    'packet=stream_index,pts_time',
    '-of',
    'json',
    input.path,
  ]);
  var done = false;
  Future<String> read(Stream<List<int>> source) async {
    final bytes = <int>[];
    await for (final chunk in source) {
      if (bytes.length + chunk.length > 4 * 1024 * 1024) throw StateError('Packet inspection size limit');
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  try {
    final result = await Future.wait<Object>([
      process.exitCode,
      read(process.stdout),
      read(process.stderr),
    ], eagerError: true).timeout(const Duration(seconds: 20));
    done = true;
    await File(p.join(output.path, 'packets.json')).writeAsString(result[1] as String);
    final report = <String, Object?>{'exitCode': result[0], 'stderr': result[2]};
    if (result[0] == 0) {
      final json = jsonDecode(result[1] as String) as Map;
      final packets = json['packets'] as List;
      report['tracks'] = [for (final stream in json['streams'] as List) _track(stream as Map, packets)];
    }
    return report;
  } finally {
    if (!done) {
      process.kill();
      await process.exitCode.timeout(const Duration(seconds: 5));
    }
  }
}

Map<String, Object?> _track(Map stream, List packets) {
  final times =
      packets
          .where((packet) => packet['stream_index'] == stream['index'] && packet['pts_time'] is String)
          .map((packet) => double.parse(packet['pts_time'] as String))
          .toList()
        ..sort();
  double gap = 0;
  for (var i = 1; i < times.length; i++) {
    if (times[i] - times[i - 1] > gap) gap = times[i] - times[i - 1];
  }
  return {
    'type': stream['codec_type'],
    'packets': times.length,
    'firstPts': times.firstOrNull,
    'lastPts': times.lastOrNull,
    'maxStep': gap,
  };
}
