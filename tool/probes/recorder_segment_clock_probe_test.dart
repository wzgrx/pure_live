// Opt-in synthetic native regression. Candidate parameters stay in this probe
// until their behavior is established; the production recorder is not patched.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/services/settings/log_controller.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_command_builder.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_manager.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_types.dart';
import 'package:pure_live/recorder/models/live_record_task.dart';
import 'package:pure_live/recorder/services/video_processor_service.dart';

import 'frame_hash_timeline.dart';

void main() {
  for (final fixture in ['av_cfr', 'av_vfr', 'video_only', 'audio_only']) {
    test(
      'native segment clock preserves $fixture content and cadence',
      () async {
        final base = Platform.environment['PURELIVE_CLOCK_PROBE_ROOT']!;
        final input = File(p.join(base, 'fixtures', '$fixture.flv'));
        expect(await input.exists(), true);
        final output = await Directory(p.join(base, 'runs', '$fixture-${DateTime.now().microsecondsSinceEpoch}'))
            .create(recursive: true);
        Hive.init(p.join(output.path, 'settings'));
        await HivePrefUtil.init();
        Get.testMode = true;
        Get.put(LogController());
        final manager = FFmpegManager.to;
        final report = <String, Object?>{
          'fixture': fixture,
          'scope': 'synthetic-Windows-native-not-device-acceptance',
          'contract': 'failed',
        };
        final results = <String, Map<String, FrameHashTimeline>>{};
        final media = [if (fixture != 'audio_only') 'video', if (fixture != 'video_only') 'audio'];
        final ownedIds = <String>[];
        try {
          results['source'] = await _decode(input, output, 'source', media);
          final variants = <String, Object?>{};
          report['variants'] = variants;
          for (final variant in ['single', 'legacy', 'candidate']) {
            report['stage'] = '$variant-record';
            final dir = await Directory(p.join(output.path, variant)).create();
            final task = LiveRecordTask.fromRoom(LiveRoom(platform: 'clockfixture', roomId: '$fixture-$variant'))
              ..outputDir = dir.path
              ..recordedSeconds = 26;
            ownedIds.add(task.taskId);
            final args = FFmpegCommandBuilder.buildRecordArguments(
              url: input.absolute.path,
              outputDir: dir.path,
              segmentTime: variant == 'single' ? 86400 : 10,
              preferBestStream: true,
              rwTimeout: 15,
              threadQueueSize: 512,
              filePrefix: task.recordingFilePrefix,
            ).toList();
            final journal = File(p.join(dir.path, 'segments.csv'));
            if (variant == 'candidate') {
              report['stage'] = '$variant-merge';
              args[args.indexOf('-segment_format_options') + 1] = 'flush_packets=1:avoid_negative_ts=disabled';
              args.insertAll(args.length - 1, ['-segment_list', journal.path, '-segment_list_type', 'csv']);
            }
            // A finite local fixture ends normally. The live service deliberately
            // reports an unsolicited EOF as a recoverable error even at code 0;
            // that network recovery contract is separate from this muxing test.
            final record = await _native(manager, task.taskId, args);
            final segments =
                (await dir.list(followLinks: false).toList())
                    .whereType<File>()
                    .where((f) => p.extension(f.path) == '.ts')
                    .toList()
                  ..sort((a, b) => a.path.compareTo(b.path));
            expect(segments.length, variant == 'single' ? 1 : greaterThanOrEqualTo(3));
            final target = File(p.join(dir.path, '${task.recordingFilePrefix}.mp4'));
            final evidence = <String, Object?>{'segments': segments.length, 'nativeRecord': record, 'arguments': args};
            variants[variant] = evidence;
            if (variant == 'candidate') {
              // The generator uses simple controlled basenames. General journal
              // validation belongs in the future production parser, not here.
              final rows = (await journal.readAsLines())
                  .where((s) => s.trim().isNotEmpty)
                  .map((s) => s.split(','))
                  .toList();
              expect(rows, hasLength(segments.length));
              final manifest = StringBuffer('ffconcat version 1.0\n');
              for (var i = 0; i < rows.length; i++) {
                expect(rows[i], hasLength(3));
                expect(rows[i][0], p.basename(segments[i].path));
                final escaped = segments[i].absolute.path.replaceAll('\\', '/').replaceAll("'", r"'\''");
                manifest.writeln("file '$escaped'\ninpoint 0");
                if (i + 1 < rows.length) {
                  final duration = double.parse(rows[i + 1][1]) - double.parse(rows[i][1]);
                  expect(duration, greaterThan(0));
                  manifest.writeln('duration ${duration.toStringAsFixed(6)}');
                }
              }
              evidence['journal'] = rows;
              final list = File(p.join(dir.path, 'candidate.ffconcat'));
              await list.writeAsString(manifest.toString());
              final id = '${task.taskId}-merge';
              ownedIds.add(id);
              evidence['nativeMerge'] = await _native(manager, id, [
                '-hide_banner',
                '-loglevel',
                'warning',
                '-xerror',
                '-f',
                'concat',
                '-safe',
                '0',
                '-i',
                list.path,
                '-map',
                '0:v?',
                '-map',
                '0:a?',
                '-c',
                'copy',
                '-movflags',
                '+faststart',
                '-f',
                'mp4',
                target.path,
              ]);
            } else {
              report['stage'] = '$variant-merge';
              expect(await VideoProcessorService.to.convertToMp4(task: task, deleteSourceTs: false), true);
            }
            expect(await target.length(), greaterThan(0));
            report['stage'] = '$variant-decode';
            results[variant] = await _decode(target, output, variant, media);
          }
          final comparisons = <String, Object?>{};
          report['stage'] = 'comparison-gates';
          report['comparisons'] = comparisons;
          for (final kind in media) {
            final reference = results['single']![kind]!;
            comparisons[kind] = {
              'sourceToSingle': results['source']![kind]!.compare(reference),
              'sourceToCandidate': results['source']![kind]!.compare(results['candidate']![kind]!),
              'singleToLegacy': reference.compare(results['legacy']![kind]!),
              'singleToCandidate': reference.compare(results['candidate']![kind]!),
            };
          }
          // Keep all variants' observations before any clock verdict fails.
          for (final kind in media) {
            final checks = comparisons[kind] as Map;
            for (final comparison in checks.values.cast<Map>()) {
              expect(comparison['orderedContentEqual'], true, reason: '$fixture/$kind');
            }
            final candidate = checks['singleToCandidate'] as Map;
            expect(
              candidate['offsetSpreadSeconds'] as double,
              lessThanOrEqualTo(kind == 'video' ? 2 / 90000 : 2 / 44100),
              reason: '$fixture/$kind candidate vs single',
            );
          }
          if (fixture == 'av_cfr') {
            final baseline = (comparisons['video'] as Map)['singleToLegacy'] as Map;
            expect(
              baseline['offsetSpreadSeconds'] as double,
              greaterThan(0.001),
              reason: 'synthetic baseline must actually reproduce drift',
            );
          }
          report['contract'] = 'passed';
        } catch (error) {
          report['error'] = error.toString();
          rethrow;
        } finally {
          for (final id in ownedIds) {
            if (manager.isRunning(id)) await manager.stop(id).timeout(const Duration(seconds: 30));
          }
          await File(p.join(output.path, 'summary.json'))
              .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
          // ignore: avoid_print
          print(jsonEncode(report));
          Get.reset();
          await Hive.close();
        }
      },
      skip: Platform.environment['PURELIVE_CLOCK_PROBE'] != '1',
      timeout: const Timeout(Duration(minutes: 6)),
    );
  }
}

Future<Map<String, Object?>> _native(FFmpegManager manager, String id, List<String> args, {bool live = false}) async {
  final evidence = <String, Object?>{};
  final ended = Completer<void>();
  final subscription = manager.stream.listen((event) {
    if (event.taskId == id && [FFmpegEventType.complete, FFmpegEventType.error].contains(event.type)) {
      evidence.addAll({
        'type': event.type.name,
        for (final key in ['code', 'manualStop', 'forcedCancel', 'inputIntegrityError', 'inputCoverageIncomplete'])
          if (event.data.containsKey(key)) key: event.data[key],
      });
      if (!ended.isCompleted) ended.complete();
    }
  });
  try {
    await manager.start(taskId: id, arguments: args, liveRecording: live).timeout(const Duration(seconds: 60));
    await ended.future.timeout(const Duration(seconds: 5));
    expect(evidence['type'], 'complete');
    expect(evidence['code'], 0);
    expect(manager.isRunning(id), false);
    return evidence;
  } finally {
    if (manager.isRunning(id)) await manager.stop(id).timeout(const Duration(seconds: 30));
    await subscription.cancel();
  }
}

Future<Map<String, FrameHashTimeline>> _decode(File input, Directory output, String label, List<String> media) async {
  final results = <String, FrameHashTimeline>{};
  for (final kind in media) {
    final process = await Process.start(Platform.environment['PURELIVE_FFMPEG']!, [
      '-v',
      'error',
      '-threads',
      '4',
      '-i',
      input.path,
      '-map',
      kind == 'video' ? '0:v:0' : '0:a:0',
      '-xerror',
      if (kind == 'video') ...[
        '-c:v',
        'rawvideo',
        '-pix_fmt',
        'yuv420p',
        '-fps_mode',
        'passthrough',
      ] else ...[
        '-c:a',
        'pcm_s16le',
      ],
      '-threads',
      '4',
      '-enc_time_base',
      'demux',
      '-f',
      'framemd5',
      '-',
    ]);
    var ended = false;
    Future<String> collect(Stream<List<int>> stream) async {
      final bytes = <int>[];
      await for (final chunk in stream) {
        if (bytes.length + chunk.length > 4 * 1024 * 1024) throw StateError('Decode evidence budget');
        bytes.addAll(chunk);
      }
      return utf8.decode(bytes);
    }

    try {
      final decoded = await Future.wait<Object>([process.exitCode, collect(process.stdout), collect(process.stderr)])
          .timeout(const Duration(seconds: 30));
      ended = true;
      await File(p.join(output.path, '$label-$kind.framemd5')).writeAsString(decoded[1] as String);
      await File(p.join(output.path, '$label-$kind.stderr')).writeAsString(decoded[2] as String);
      expect(decoded[0], 0);
      expect((decoded[2] as String).trim(), isEmpty);
      results[kind] = FrameHashTimeline.parse(decoded[1] as String);
    } finally {
      if (!ended) {
        process.kill();
        await process.exitCode.timeout(const Duration(seconds: 5));
      }
    }
  }
  return results;
}
