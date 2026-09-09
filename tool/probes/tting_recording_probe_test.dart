// Opt-in real Windows FFmpegKit recording/finalization. Public short media is
// retained only in the caller's ignored output directory; credentials and
// signed input URLs are never written by this probe.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:pure_live/core/common/http_client.dart' as app_http;
import 'package:pure_live/core/sites.dart';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/services/settings/log_controller.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/site/tting/tting_site.dart';
import 'package:pure_live/core/site/tting/tting_api.dart';
import 'package:pure_live/recorder/services/recorder_proxy_routing.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_command_builder.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_manager.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_types.dart';
import 'package:pure_live/recorder/models/live_record_task.dart';
import 'package:pure_live/recorder/services/ffmpeg_header_factory.dart';
import 'package:pure_live/recorder/services/recording_output_metrics.dart';
import 'package:pure_live/recorder/services/stream_resolver_service.dart';
import 'package:pure_live/recorder/services/video_processor_service.dart';

void main() {
  test(
    'TTing production resolver, native segment growth, stop, MP4 commit and independent decode',
    () async {
      final outputRoot = Platform.environment['PURELIVE_RECORDING_PROBE_OUTPUT'];
      final ffprobe = Platform.environment['PURELIVE_FFPROBE'];
      final ffmpeg = Platform.environment['PURELIVE_FFMPEG'];
      expect(outputRoot, isNotEmpty);
      expect(ffprobe, isNotEmpty);
      expect(ffmpeg, isNotEmpty);
      const route = 'PROXY 127.0.0.1:7897';
      var upstreamProxyRequests = 0;
      configureRecorderProxyRouting((_) {
        upstreamProxyRequests++;
        return route;
      });
      final hive = await Directory.systemTemp.createTemp('purelive-recording-probe-settings-');
      Hive.init(hive.path);
      await HivePrefUtil.init();
      Get.testMode = true;
      Get.put(LogController());
      final output = await Directory(p.join(outputRoot!, 'TTing 录制 ${DateTime.now().microsecondsSinceEpoch}'))
          .create(recursive: true);
      final manager = FFmpegManager.to;
      LiveRecordTask? task;
      Future<void>? recording;
      StreamSubscription<Object?>? events;
      StreamSubscription<VideoProcessEvent>? mergeEvents;
      var stage = 'official-metadata';
      try {
        await HttpOverrides.runWithHttpOverrides(() async {
          final previous = app_http.HttpClient.instance.dio;
          final dio = Dio(
            BaseOptions(connectTimeout: const Duration(seconds: 12), receiveTimeout: const Duration(seconds: 20)),
          )..httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => HttpClient()..findProxy = (_) => route);
          app_http.HttpClient.instance.dio = dio;
          try {
            final site = Sites.of('ttinglive').liveSite as TtingSite;
            final directory = await site.getDirectoryPage();
            expect(directory.rooms, isNotEmpty);
            final author = directory.rooms.first.roomId!;
            stage = 'room-details';
            final detail = await site.getRoomDetail(roomId: author, platform: site.id);
            final broadcast = detail.data as TtingBroadcast;
            final qualities = await site.getPlayQualites(detail: detail);
            final quality = qualities.singleWhere((item) => item.selectionId == 720);
            stage = 'recording-source-resolution';
            final source = await StreamResolverService().resolveStream(
              roomId: author,
              platform: site.id,
              preferredQuality: quality.quality,
            );
            expect(source.qualityCursorId, quality.selectionId.toString());
            expect(source.invalidAt!.isAfter(DateTime.now().toUtc()), isTrue);
            expect(source.sourceQueryPolicy!.matchesSource(Uri.parse(source.url)), isTrue);
            final current = LiveRecordTask.fromRoom(
              LiveRoom(platform: 'ttinglive', roomId: author, nick: 'TTing probe'),
            )..outputDir = output.path;
            task = current;
            final headers = await FFmpegHeaderFactory.build(platform: 'ttinglive', roomId: author);
            final arguments = FFmpegCommandBuilder.buildRecordArguments(
              url: source.url,
              outputDir: output.path,
              segmentTime: 10,
              preferBestStream: true,
              rwTimeout: 10,
              threadQueueSize: 512,
              filePrefix: current.recordingFilePrefix,
              headers: headers,
            );
            stage = 'native-initialization';
            await manager.initialize();
            final version = FFmpegKitExtended.getFFmpegVersion();
            final observed = <String>[];
            events = manager.stream.listen((event) {
              if (event.taskId == current.taskId) observed.add(event.type.name);
            });
            final tracker = const RecordingOutputMetrics().track(
              directoryPath: output.path,
              filePrefix: current.recordingFilePrefix,
            );
            final samples = <int>[];
            var ended = false;
            Object? startError;
            stage = 'native-recording';
            recording = manager
                .start(
                  taskId: current.taskId,
                  arguments: arguments,
                  liveRecording: true,
                  sourceQueryPolicy: source.sourceQueryPolicy,
                )
                .then<void>(
                  (_) {
                    ended = true;
                  },
                  onError: (Object error) {
                    startError = error;
                    ended = true;
                  },
                );
            final captureClock = Stopwatch()..start();
            final captureSamples = <Map<String, int>>[];
            int? firstBytesMs;
            var captureTargetReached = false;
            // Bound startup separately from the requested media coverage.
            // A wall-clock sleep can finish while HLS is still probing tracks.
            for (var second = 0; second < 100 && !ended; second++) {
              await Future<void>.delayed(const Duration(seconds: 1));
              final snapshot = await tracker.sample();
              final recordedSeconds = manager.getSession(current.taskId)?.recordedSeconds ?? 0;
              samples.add(snapshot.bytes);
              if (snapshot.bytes > 0) firstBytesMs ??= captureClock.elapsedMilliseconds;
              captureSamples.add({
                'elapsedMs': captureClock.elapsedMilliseconds,
                'bytes': snapshot.bytes,
                'segments': snapshot.segmentCount,
                'recordedSeconds': recordedSeconds,
              });
              if (snapshot.segmentCount >= 2 && recordedSeconds >= 30) {
                captureTargetReached = true;
                break;
              }
            }
            captureClock.stop();
            await File(p.join(output.path, 'capture-samples.json')).writeAsString(
              jsonEncode({
                'samples': captureSamples,
                'firstBytesMs': firstBytesMs,
                'targetReached': captureTargetReached,
                'nativeEvents': observed,
              }),
            );
            expect(startError, isNull, reason: 'Native recording must open the selected production input.');
            expect(ended, isFalse, reason: 'The live input must remain active until the explicit stop.');
            final session = manager.getSession(current.taskId);
            current.recordedSeconds = session?.recordedSeconds ?? 0;
            stage = 'native-stop';
            await manager.stop(current.taskId);
            await recording!.timeout(const Duration(seconds: 15));
            expect(manager.isRunning(current.taskId), isFalse);
            expect(observed, contains(FFmpegEventType.started.name));
            expect(observed, contains(FFmpegEventType.complete.name));
            final segments = await const RecordingOutputMetrics().measure(
              directoryPath: output.path,
              filePrefix: current.recordingFilePrefix,
            );
            expect(
              captureTargetReached,
              isTrue,
              reason: 'Bounded capture did not reach 30 media seconds and two segments.',
            );
            expect(segments.segmentCount, greaterThanOrEqualTo(2));
            expect(samples.where((bytes) => bytes > 0).toSet().length, greaterThanOrEqualTo(3));
            for (var index = 1; index < samples.length; index++) {
              expect(samples[index], greaterThanOrEqualTo(samples[index - 1]));
            }
            expect(segments.bytes, greaterThan(100 * 1024));
            current.fileSize = segments.bytes;
            // Retain diagnostic input copies before the production finalizer commits.
            // They live below a distinct subdirectory and never enter its manifest.
            final retained = await Directory(p.join(output.path, 'probe-source')).create();
            await for (final entry in output.list()) {
              if (entry is File && p.extension(entry.path) == '.ts') {
                await entry.copy(p.join(retained.path, p.basename(entry.path)));
              }
            }
            stage = 'production-mp4-finalization';
            final mergeProgress = <double>[];
            VideoProcessEvent? mergedEvent;
            mergeEvents = VideoProcessorService.to.stream.listen((event) {
              if (event.taskId != current.taskId) return;
              if (event.type == VideoProcessEventType.progress) mergeProgress.add(event.progress);
              if (event.type == VideoProcessEventType.completed) mergedEvent = event;
            });
            expect(await VideoProcessorService.to.convertToMp4(task: current), isTrue);
            await Future<void>.delayed(Duration.zero);
            expect(mergedEvent?.progress, 1);
            expect(mergeProgress.every((value) => value >= 0 && value < 1), isTrue);
            expect(VideoProcessorService.to.isProcessing(current.taskId), isFalse);
            final committed = await const RecordingOutputMetrics().measureFinalized(
              directoryPath: output.path,
              filePrefix: current.recordingFilePrefix,
            );
            expect(committed.bytes, greaterThan(100 * 1024));
            final remaining = await const RecordingOutputMetrics().measure(
              directoryPath: output.path,
              filePrefix: current.recordingFilePrefix,
            );
            expect(remaining.segmentCount, 0);
            final mp4 = p.join(output.path, '${current.recordingFilePrefix}.mp4');
            expect(await File(mp4).length(), committed.bytes);
            stage = 'independent-file-inspection';
            final inspection = await _runOwned(ffprobe!, [
              '-v',
              'error',
              '-show_streams',
              '-show_format',
              '-of',
              'json',
              mp4,
            ], timeout: const Duration(seconds: 15));
            expect(inspection.exitCode, 0);
            final metadata = jsonDecode(inspection.stdout as String) as Map<String, dynamic>;
            final format = metadata['format'] as Map<String, dynamic>;
            final duration = double.parse(format['duration'] as String);
            final streams = (metadata['streams'] as List).cast<Map<String, dynamic>>();
            expect(duration, greaterThan(15));
            expect(duration, lessThan(40));
            expect(streams.any((stream) => stream['codec_type'] == 'audio'), isTrue);
            final video = streams.singleWhere((stream) => stream['codec_type'] == 'video');
            expect(video['height'], 720, reason: 'Native output must match the requested 720p quality.');
            expect(upstreamProxyRequests, greaterThan(0));
            stage = 'independent-decode';
            final decode = await _runOwned(ffmpeg!, [
              '-v',
              'error',
              '-i',
              mp4,
              '-xerror',
              // Preserve the demux clock for VFR input: rounding decoded frames
              // to the nominal FPS can manufacture null-mux DTS collisions.
              '-fps_mode',
              'passthrough',
              '-enc_time_base',
              'demux',
              '-f',
              'null',
              '-',
            ], timeout: const Duration(seconds: 30));
            await File(p.join(output.path, 'decode-diagnostics.json')).writeAsString(
              jsonEncode({
                'exitCode': decode.exitCode,
                'stderr': decode.stderr,
                'scope': 'entire-output-with-xerror-and-demux-clock',
              }),
            );
            expect(decode.exitCode, 0);
            expect((decode.stderr as String).trim(), isEmpty, reason: 'Exit zero alone is not clean decoding.');
            final summary = {
              'probe': 'tting-production-native-recording',
              'utc': DateTime.now().toUtc().toIso8601String(),
              'transport': 'hls',
              'sourceFamily': broadcast.sources.first.family,
              'ownerUid': author,
              'directoryCards': directory.rooms.length,
              'nativeEvents': observed,
              'sourceLeaseCurrentAtOpen': true,
              'sourceQueryPolicyPassedToNativeManager': true,
              'requestedHeight': 720,
              'nativeHeight': video['height'],
              'firstBytesMs': firstBytesMs,
              'captureTargetReached': captureTargetReached,
              'trackStartTimes': streams
                  .map((s) => {'type': s['codec_type'], 'startTime': s['start_time'], 'duration': s['duration']})
                  .toList(),
              'upstreamProxyRequests': upstreamProxyRequests,
              'nativeFfmpeg': version,
              'quality': source.quality.quality,
              'qualityId': source.qualityCursorId,
              'segmentCount': segments.segmentCount,
              'provisionalBytes': segments.bytes,
              'committedBytes': committed.bytes,
              'finalizedMetricMatchesFile': true,
              'output': mp4,
              'durationSeconds': duration,
              'growthSamples': samples,
              'nativeStopped': true,
              'registeredProductionResolver': true,
              'routing':
                  'Clash 7897 for production Dio API and production recorder relay; loopback direct; UI not covered',
              'finalizerReleased': true,
              'sourceSegmentsRemovedAfterCommit': true,
              'independentDecodeExit': decode.exitCode,
              'independentDecodeScope': 'entire-output-with-xerror-and-demux-clock',
              'independentDecodeStderrEmpty': true,
              'diagnosticSourceCopiesRetained': true,
              'mergeProgressSamples': mergeProgress,
              'streams': streams
                  .map(
                    (s) => {
                      'type': s['codec_type'],
                      'codec': s['codec_name'],
                      'width': s['width'],
                      'height': s['height'],
                    },
                  )
                  .toList(),
              'credentialsPersisted': false,
              'evidenceLayer': 'windows-native-recording-and-finalization-not-device-ui-or-long-duration',
            };
            await File(p.join(output.path, 'summary.json'))
                .writeAsString(const JsonEncoder.withIndent('  ').convert(summary));
            // ignore: avoid_print
            print(jsonEncode(summary));
          } finally {
            app_http.HttpClient.instance.dio = previous;
            dio.close(force: true);
          }
        }, _RealNetwork());
      } catch (error) {
        await File(p.join(output.path, 'failure.json')).writeAsString(
          jsonEncode({
            'stage': stage,
            'type': error.runtimeType.toString(),
            'invariant': error is TestFailure ? error.message?.replaceAll(RegExp(r'https?://[^\s]+'), '[url]') : null,
          }),
        );
        fail('TTing recording probe failed at $stage (${error.runtimeType})');
      } finally {
        if (task != null && manager.isRunning(task!.taskId)) await manager.stop(task!.taskId);
        await recording?.timeout(const Duration(seconds: 15));
        await events?.cancel();
        await mergeEvents?.cancel();
        Get.reset();
        await Hive.close();
        configureRecorderProxyRouting(null);
        if (!p.isWithin(Directory.systemTemp.absolute.path, hive.absolute.path) ||
            !p.basename(hive.path).startsWith('purelive-recording-probe-settings-')) {
          throw StateError('Unexpected temporary settings path');
        }
        await hive.delete(recursive: true);
      }
    },
    skip: Platform.environment['PURELIVE_TTING_RECORDING_PROBE'] != '1',
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'retained TTing segments finalize and fully decode independently of capture gate',
    _retainedFinalization,
    skip: Platform.environment['PURELIVE_TTING_FINALIZE_RETAINED'] != '1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _RealNetwork extends HttpOverrides {}

Future<ProcessResult> _runOwned(String executable, List<String> arguments, {required Duration timeout}) async {
  final process = await Process.start(executable, arguments);
  var completed = false;
  Future<String> collect(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > 1024 * 1024) throw StateError('Inspection output limit');
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  try {
    final result = await Future.wait<Object>([
      process.exitCode,
      collect(process.stdout),
      collect(process.stderr),
    ], eagerError: true).timeout(timeout);
    completed = true;
    return ProcessResult(process.pid, result[0] as int, result[1], result[2]);
  } finally {
    if (!completed) {
      process.kill();
      await process.exitCode.timeout(const Duration(seconds: 5));
    }
  }
}

// Read-only retained inputs; no API requests and no capture-success assertion.
Future<void> _retainedFinalization() async {
  final sourcePath = Platform.environment['PURELIVE_RETAINED_TS'];
  final base = Platform.environment['PURELIVE_RECORDING_PROBE_OUTPUT'];
  expect(sourcePath, isNotEmpty);
  expect(base, isNotEmpty);
  final originals = await Directory(sourcePath!)
      .list(followLinks: false)
      .where((entry) => entry is File && p.extension(entry.path) == '.ts')
      .cast<File>()
      .toList();
  originals.sort((a, b) => a.path.compareTo(b.path));
  expect(originals, hasLength(2));
  final output = await Directory(p.join(base!, 'retained-${DateTime.now().microsecondsSinceEpoch}'))
      .create(recursive: true);
  final settings = await Directory.systemTemp.createTemp('purelive-tting-retained-settings-');
  Hive.init(settings.path);
  await HivePrefUtil.init();
  Get.testMode = true;
  Get.put(LogController());
  final task = LiveRecordTask.fromRoom(LiveRoom(platform: 'ttinglive', roomId: 'retained', nick: 'retained probe'))
    ..outputDir = output.path;
  final report = <String, Object?>{'networkUsed': false, 'captureGatePassed': false, 'contract': 'failed'};
  try {
    for (var index = 0; index < originals.length; index++) {
      await originals[index].copy(
        p.join(output.path, '${task.recordingFilePrefix}_${index.toString().padLeft(6, '0')}.ts'),
      );
    }
    final result = await VideoProcessorService.to.convertToMp4(task: task);
    report['productionFinalizerSuccess'] = result;
    report['finalizerReleased'] = !VideoProcessorService.to.isProcessing(task.taskId);
    expect(result, isTrue);
    final mp4 = p.join(output.path, '${task.recordingFilePrefix}.mp4');
    final inspection = await _runOwned(Platform.environment['PURELIVE_FFPROBE']!, [
      '-v',
      'error',
      '-show_streams',
      '-show_format',
      '-of',
      'json',
      mp4,
    ], timeout: const Duration(seconds: 20));
    expect(inspection.exitCode, 0);
    final metadata = jsonDecode(inspection.stdout as String) as Map<String, dynamic>;
    final streams = (metadata['streams'] as List).cast<Map<String, dynamic>>();
    final duration = double.parse((metadata['format'] as Map<String, dynamic>)['duration'] as String);
    report.addAll({
      'output': mp4,
      'bytes': await File(mp4).length(),
      'durationSeconds': duration,
      'streams': streams
          .map(
            (s) => {
              'type': s['codec_type'],
              'codec': s['codec_name'],
              'width': s['width'],
              'height': s['height'],
              'startTime': s['start_time'],
              'duration': s['duration'],
            },
          )
          .toList(),
      'copiedTsRemaining': await output.list().where((entry) => p.extension(entry.path) == '.ts').length,
      'originalsStillPresent': await Future.wait(originals.map((file) => file.exists())),
    });
    final decode = await _runOwned(Platform.environment['PURELIVE_FFMPEG']!, [
      '-v',
      'error',
      '-i',
      mp4,
      '-xerror',
      '-fps_mode',
      'passthrough',
      '-enc_time_base',
      'demux',
      '-f',
      'null',
      '-',
    ], timeout: const Duration(seconds: 30));
    await File(p.join(output.path, 'decode-diagnostics.json'))
        .writeAsString(jsonEncode({'exitCode': decode.exitCode, 'stderr': decode.stderr}));
    report['fullDecodeExit'] = decode.exitCode;
    report['fullDecodeStderrEmpty'] = (decode.stderr as String).trim().isEmpty;
    expect(streams.singleWhere((stream) => stream['codec_type'] == 'video')['height'], 720);
    expect(streams.any((stream) => stream['codec_type'] == 'audio'), isTrue);
    expect(duration, inExclusiveRange(15, 45));
    expect(decode.exitCode, 0);
    expect((decode.stderr as String).trim(), isEmpty);
    expect(report['copiedTsRemaining'], 0);
    expect(report['originalsStillPresent'], everyElement(isTrue));
    expect(report['finalizerReleased'], isTrue);
    report['contract'] = 'passed';
  } finally {
    await File(p.join(output.path, 'summary.json')).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    // ignore: avoid_print
    print(jsonEncode(report));
    Get.reset();
    await Hive.close();
    if (!p.isWithin(Directory.systemTemp.absolute.path, settings.absolute.path) ||
        !p.basename(settings.path).startsWith('purelive-tting-retained-settings-')) {
      throw StateError('Unexpected retained settings path');
    }
    await settings.delete(recursive: true);
  }
}
