import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:live_cli/src/lease/lease_command.dart';
import 'package:live_cli/src/probe/sites.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:live_record/live_record.dart';
import 'package:path/path.dart' as p;

/// Checks a recorded FLV file with the same timestamp rules as `lease`.
Future<LeaseReport> checkFlvFile(String path, {int gapMs = 500}) async {
  final report = LeaseReport(gapMs: gapMs);
  final framer = FlvFramer();
  await for (final chunk in File(path).openRead()) {
    framer.add(chunk).forEach(report.add);
  }
  return report;
}

/// Largest step between consecutive values, and how many went backwards.
({double maxStep, int backwards, int count}) stepReport(Iterable<double> values) {
  double? last;
  var maxStep = 0.0;
  var backwards = 0;
  var count = 0;
  for (final value in values) {
    count++;
    final previous = last;
    last = value;
    if (previous == null) continue;
    final step = value - previous;
    if (step < 0) backwards++;
    if (step > maxStep) maxStep = step;
  }
  return (maxStep: maxStep, backwards: backwards, count: count);
}

/// Video packet DTS values of [path] from `ffprobe` (spec §22 gate method), or
/// null when ffprobe is not installed.
Future<List<double>?> ffprobeVideoDts(String path) async {
  try {
    final result = await Process.run('ffprobe', [
      '-v',
      'error',
      '-select_streams',
      'v',
      '-show_entries',
      'packet=dts_time',
      '-of',
      'csv=p=0',
      path,
    ]);
    if (result.exitCode != 0) return const [];
    return [
      for (final line in (result.stdout as String).split('\n')) ?double.tryParse(line.trim().replaceAll(',', '')),
    ];
  } on ProcessException {
    return null;
  }
}

/// A [Remuxer] over the `ffmpeg` executable (desktop tools only; the app
/// uses a libavformat shim, ADR 0005 §4). Any error output fails the job.
final class FfmpegProcessRemuxer implements Remuxer {
  /// Creates the remuxer; [executable] defaults to `ffmpeg` on PATH.
  const new({this.executable = 'ffmpeg'});

  /// ffmpeg executable.
  final String executable;

  @override
  Future<void> remux(RemuxJob job) async {
    final process = await Process.start(executable, [
      '-hide_banner',
      '-nostdin',
      '-v',
      'error',
      '-i',
      job.input,
      '-map',
      '0',
      '-c',
      'copy',
      '-movflags',
      '+faststart',
      '-f',
      'mp4',
      '-progress',
      'pipe:1',
      '-y',
      job.output,
    ]);
    unawaited(job.cancelled.then((_) => process.kill()));
    final errors = StringBuffer();
    final stderrDone = process.stderr.transform(utf8.decoder).forEach(errors.write);
    await process.stdout.transform(utf8.decoder).transform(const LineSplitter()).forEach((line) {
      // Stream copy writes about as many bytes as it reads.
      if (line.startsWith('total_size=')) {
        final bytes = int.tryParse(line.substring('total_size='.length));
        if (bytes != null) job.onProgress(bytes < job.inputBytes ? bytes : job.inputBytes);
      }
    });
    await stderrDone;
    final code = await process.exitCode;
    if (code != 0 || errors.isNotEmpty) {
      throw RemuxException('ffmpeg exit $code: ${errors.toString().trim()}');
    }
  }
}

final class _LoggingRooms implements RecordRooms {
  new(this._inner, this._log);

  final RecordRooms _inner;
  final void Function(String) _log;
  int resolves = 0;

  @override
  Future<RoomDetail> detail(RoomRef room) async {
    final detail = await _inner.detail(room);
    _log('check    ${detail.card.state.name} · ${detail.card.anchorName}');
    return detail;
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    resolves++;
    final set = await _inner.streams(room, quality: quality);
    final lease = set.lines.firstOrNull?.lease;
    _log(
      'resolve  #$resolves ${set.selected.label} · ${set.lines.map((line) => line.lineId).join(', ')}'
      '${lease == null ? '' : ' · refresh ${lease.refreshAt.toLocal()} · cuts=${lease.cutsConnection}'}',
    );
    return set;
  }
}

/// `live_cli record <platform> <room>`: records a live room with the v4
/// recorder (`live_record`) for a while, then checks the files: timestamp
/// steps and gaps of each FLV segment (as `lease` does for the relay), the
/// session's `gaps.json`, and with ffprobe the video DTS of the FLV and MP4.
class RecordCommand extends Command<int> {
  /// Creates the command.
  new() {
    argParser
      ..addOption('duration', defaultsTo: '420', help: 'Seconds to record.')
      ..addOption('out', help: 'Recording root; a temporary folder by default.')
      ..addOption('proxy', help: 'host:port of an HTTP proxy for this platform; direct by default.')
      ..addOption('quality', allowed: [for (final q in RecordQuality.values) q.name], help: 'Quality preference.')
      ..addOption('split-minutes', defaultsTo: '0', help: 'Split segments every N minutes (0: never).')
      ..addFlag('remux', help: 'Remux to MP4 with ffmpeg afterwards (sources kept for the check).')
      ..addOption('gap-ms', defaultsTo: '500', help: 'A timestamp step above this counts as a gap.');
  }

  @override
  String get name => 'record';

  @override
  String get description => 'Record a live room with the v4 recorder and check the files for gaps.';

  @override
  String get invocation => 'live_cli record <platform> <room id or link> [options]';

  @override
  Future<int> run() async {
    final options = argResults!;
    if (options.rest.length != 2) usageException('Expected <platform> <room id or link>.');
    final [platform, input] = options.rest;
    final factory = siteFactories[platform];
    if (factory == null) usageException('No v4 adapter for "$platform" (have: ${siteFactories.keys.join(', ')}).');
    final duration = Duration(seconds: int.parse(options.option('duration')!));
    final gapMs = int.parse(options.option('gap-ms')!);
    final proxy = options.option('proxy');
    final route = proxy == null
        ? const DirectRoute()
        : HttpProxyRoute(proxy.split(':').first, int.parse(proxy.split(':').last));
    final policy = FixedProxyPolicy(global: route);
    final http = IoLiveHttp(proxy: policy);
    final site = factory(http);
    final out = options.option('out') ?? (await Directory.systemTemp.createTemp('live_cli_record')).path;
    final remux = options.flag('remux');
    final wall = Stopwatch()..start();
    void log(String text) =>
        stdout.writeln('[${(wall.elapsedMilliseconds / 1000).toStringAsFixed(1).padLeft(6)} s] $text');

    RecordManager? manager;
    try {
      final ref = await (site as LinkResolver).resolve(input);
      if (ref == null) {
        stderr.writeln('Not a $platform room: $input');
        return 1;
      }
      final detail = await (site as RoomSource).detail(ref);
      log('room     ${ref.key} · ${detail.card.state.name} · ${detail.card.anchorName} · ${detail.card.title}');
      if (detail.card.state == LiveState.offline) {
        log('stopped  the room is not live');
        return 2;
      }
      final quality = options.option('quality');
      final rooms = _LoggingRooms(SiteRecordRooms((id) => id == platform ? site : null), log);
      manager = RecordManager(
        rooms: rooms,
        store: JsonFileRecordTaskStore(p.join(out, 'record_tasks.json')),
        root: out,
        settings: RecordSettings(
          defaultQuality: quality == null ? RecordQuality.original : RecordQuality.values.byName(quality),
          splitMinutes: int.parse(options.option('split-minutes')!),
          remuxToMp4: remux,
          keepSourceAfterRemux: true,
        ),
        opener: httpRecordOpener(proxy: policy),
        remuxer: remux ? const FfmpegProcessRemuxer() : null,
      );
      await manager.init();
      RecordState? lastState;
      final updates = manager.updates.listen((task) {
        if (task.state != lastState) {
          lastState = task.state;
          log(
            'state    ${task.state.name}'
            '${task.retrying == null ? '' : ' (${task.retrying!.kind.name})'}'
            '${task.failure == null ? '' : ' · ${task.failure}'}',
          );
        }
      });
      final ticker = Timer.periodic(const Duration(seconds: 30), (_) {
        final task = manager!.task(ref.key);
        final session = task?.session;
        if (task == null || session == null) return;
        log(
          'progress ${session.media.inSeconds} s media · ${(session.bytes / 1048576).toStringAsFixed(1)} MiB · '
          '${(task.bitsPerSecond / 1000).round()} kbit/s · ${session.connections} connections · '
          '${session.splices} splices · ${session.gaps} gaps',
        );
      });
      await manager.add(detail);
      await Future<void>.delayed(duration);
      ticker.cancel();
      log('stopping');
      await manager.stop(ref.key);
      await updates.cancel();
      final task = manager.task(ref.key)!;
      final session = task.session;
      if (session == null) {
        log('failed   no session: ${task.failure}');
        return 1;
      }

      stdout
        ..writeln()
        ..writeln('record report · $platform ${ref.roomId}')
        ..writeln('  state           ${task.state.name}${task.failure == null ? '' : ' · ${task.failure}'}')
        ..writeln('  directory       ${session.layout.directory}')
        ..writeln('  media           ${session.media.inSeconds} s over ${wall.elapsed.inSeconds} s wall')
        ..writeln('  resolves        ${rooms.resolves} (first resolve + renewals + prefetches)')
        ..writeln('  connections     ${session.connections} outer, ${session.splices} spliced renewals');
      var clean = task.failure == null;
      for (final path in session.segments) {
        final report = await checkFlvFile(path, gapMs: gapMs);
        stdout
          ..writeln(
            '  segment         ${p.basename(path)} · ${(File(path).lengthSync() / 1048576).toStringAsFixed(1)} MiB',
          )
          ..writeln(
            '    tags          ${report.video.length} video, ${report.audioTags} audio, ${report.scripts} script',
          )
          ..writeln(
            '    timestamps    ${report.video.firstOrNull} → ${report.video.lastOrNull} ms '
            '(${report.videoSpan.inSeconds} s)',
          )
          ..writeln('    max step      video ${report.maxVideoStep} ms, audio ${report.maxAudioStep} ms')
          ..writeln('    backwards     video ${report.videoBackwards}, audio ${report.audioBackwards}')
          ..writeln('    gaps > $gapMs ms ${report.gaps.length}');
        for (final gap in report.gaps.take(10)) {
          stdout.writeln('      ${gap.stream} ${gap.from} → ${gap.to} (${gap.to - gap.from} ms)');
        }
        clean = clean && report.clean;
        final dts = await ffprobeVideoDts(path);
        if (dts != null) {
          final steps = stepReport(dts);
          stdout.writeln(
            '    ffprobe DTS   ${steps.count} packets, max step ${(steps.maxStep * 1000).round()} ms, '
            '${steps.backwards} backwards',
          );
          clean = clean && steps.backwards == 0;
        }
      }
      for (final path in session.outputs) {
        final dts = await ffprobeVideoDts(path);
        final steps = dts == null ? null : stepReport(dts);
        stdout.writeln(
          '  mp4             ${p.basename(path)}'
          '${steps == null ? '' : ' · ${steps.count} packets, max DTS step ${(steps.maxStep * 1000).round()} ms, '
                    '${steps.backwards} backwards'}',
        );
      }
      final gapsFile = File(session.layout.gaps);
      if (gapsFile.existsSync()) {
        final gaps = (jsonDecode(gapsFile.readAsStringSync()) as Map<String, Object?>)['gaps']! as List<Object?>;
        stdout.writeln('  gaps.json       ${gaps.length} entries');
        for (final gap in gaps.take(10)) {
          stdout.writeln('    $gap');
        }
        clean = clean && gaps.isEmpty;
      }
      stdout.writeln('  result          ${clean ? 'PASS' : 'FAIL'}');
      return clean ? 0 : 1;
    } on SiteError catch (error) {
      log('failed   $error');
      return 2;
    } finally {
      await manager?.dispose();
      http.close();
    }
  }
}
