import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:live_cli/src/lease/lease_command.dart';
import 'package:live_cli/src/probe/sites.dart';
import 'package:live_cli/src/record/remux_command.dart';
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

/// A [Remuxer] over the `ffmpeg` executable, for comparison with the
/// pure-Dart [Mp4Remuxer] the app uses (ADR 0021). Any error output fails
/// the job.
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
  new(this._inner, this._log, {this.format, this.lineId, this.renewAfter});

  final RecordRooms _inner;
  final void Function(String) _log;

  /// Only lines of this format are offered to the recorder (`--format`).
  final StreamFormat? format;

  /// Only lines whose id contains this are offered (`--line`).
  final String? lineId;

  /// Every line gets a lease that asks for renewal this long after the
  /// resolve (`--renew-after`): exercises lease renewals on real streams.
  final Duration? renewAfter;
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
    var set = await _inner.streams(room, quality: quality);
    final only = format;
    final id = lineId;
    final renew = renewAfter;
    if (only != null || id != null || renew != null) {
      set = StreamSet(
        qualities: set.qualities,
        selected: set.selected,
        lines: [
          for (final line in set.lines)
            if ((only == null || line.format == only) && (id == null || line.lineId.contains(id)))
              if (renew == null)
                line
              else
                StreamLine(
                  url: line.url,
                  format: line.format,
                  lineId: line.lineId,
                  requested: line.requested,
                  confirmed: line.confirmed,
                  headers: line.headers,
                  codec: line.codec,
                  lease: Lease(refreshAt: DateTime.now().add(renew), cutsConnection: false),
                ),
        ],
      );
    }
    final lease = set.lines.firstOrNull?.lease;
    _log(
      'resolve  #$resolves ${set.selected.label} · '
      '${set.lines.map((line) => '${line.lineId} ${line.format.name}').join(', ')}'
      '${lease == null ? '' : ' · refresh ${lease.refreshAt.toLocal()} · cuts=${lease.cutsConnection}'}',
    );
    return set;
  }
}

/// The line format of a bare stream address, by the IPTV rule
/// (spec/modules/iptv.md §5): `.m3u8` / `.m3u` is HLS, `.flv` FLV, any other
/// http(s) address a single HTTP stream the recorder sniffs (§8).
StreamFormat urlFormat(Uri url) {
  final path = url.path.toLowerCase();
  if (path.endsWith('.m3u8') || path.endsWith('.m3u')) return StreamFormat.hls;
  if (path.endsWith('.flv')) return StreamFormat.flv;
  return StreamFormat.other;
}

/// A "room" that is one stream address (`live_cli record url <address>`):
/// always live, one quality, one line. For IPTV sources such as udpxy.
final class UrlRecordRooms implements RecordRooms {
  /// Creates the rooms for [url], with request [headers].
  new(this.url, {this.headers = const {}});

  /// The stream.
  final Uri url;

  /// Request headers of the line (lower-case names).
  final Map<String, String> headers;

  static const _original = Quality(id: 'original', label: '原画', rank: 0);

  /// The room of [url].
  RoomRef get ref => RoomRef('url', url.host.isEmpty ? 'stream' : url.host);

  @override
  Future<RoomDetail> detail(RoomRef room) async => RoomDetail(
    card: RoomCard(ref: ref, title: url.path, anchorName: url.host, state: LiveState.live),
    link: url,
  );

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async => StreamSet(
    qualities: const [_original],
    selected: _original,
    lines: [
      StreamLine(
        url: url,
        format: urlFormat(url),
        lineId: 'url',
        requested: _original,
        confirmed: _original,
        headers: headers,
      ),
    ],
  );
}

/// `live_cli record <platform> <room>`: records a live room with the v4
/// recorder (`live_record`) for a while, then checks the files: timestamp
/// steps and gaps of each FLV segment (as `lease` does for the relay),
/// packets and a full decode of HLS segments (`.ts`, `.m4s`), the
/// session's `gaps.json`, and with ffprobe the video DTS of the segments and MP4.
/// `live_cli record url <address>` records one stream address instead of a
/// room (IPTV: udpxy, `.ts`, HLS).
class RecordCommand extends Command<int> {
  /// Creates the command.
  new() {
    argParser
      ..addOption('duration', defaultsTo: '420', help: 'Seconds to record.')
      ..addOption('out', help: 'Recording root; a temporary folder by default.')
      ..addOption('proxy', help: 'host:port of an HTTP proxy for this platform; direct by default.')
      ..addOption('quality', allowed: [for (final q in RecordQuality.values) q.name], help: 'Quality preference.')
      ..addOption(
        'format',
        allowed: ['flv', 'hls', 'other'],
        help: 'Offer only lines of this format to the recorder (other: single HTTP streams).',
      )
      ..addOption('line', help: 'Offer only lines whose id contains this text (Bilibili: fmp4).')
      ..addOption('renew-after', help: 'Seconds after each resolve at which the recorder renews the line (lease test).')
      ..addOption('split-minutes', defaultsTo: '0', help: 'Split segments every N minutes (0: never).')
      ..addFlag('remux', help: 'Remux to MP4 afterwards (sources kept for the check).')
      ..addOption(
        'remuxer',
        allowed: ['dart', 'ffmpeg'],
        defaultsTo: 'dart',
        help: 'With --remux: the pure-Dart remuxer the app uses (FLV, MPEG-TS, fMP4), or the ffmpeg executable.',
      )
      ..addOption('gap-ms', defaultsTo: '500', help: 'A timestamp step above this counts as a gap.')
      ..addOption('max-gaps', defaultsTo: '0', help: 'gaps.json entries a passing recording may have.')
      ..addOption('user-agent', help: 'record url: User-Agent of the requests.');
  }

  @override
  String get name => 'record';

  @override
  String get description => 'Record a live room with the v4 recorder and check the files for gaps.';

  @override
  String get invocation => 'live_cli record <platform> <room id or link> [options] | live_cli record url <address>';

  @override
  Future<int> run() async {
    final options = argResults!;
    if (options.rest.length != 2) usageException('Expected <platform> <room id or link>.');
    final [platform, input] = options.rest;
    final factory = siteFactories[platform];
    final address = platform == 'url' ? Uri.tryParse(input) : null;
    if (platform == 'url' && (address == null || !(address.isScheme('http') || address.isScheme('https')))) {
      usageException('record url needs an http(s) address.');
    }
    if (factory == null && address == null) {
      usageException('No v4 adapter for "$platform" (have: url, ${siteFactories.keys.join(', ')}).');
    }
    final duration = Duration(seconds: int.parse(options.option('duration')!));
    final gapMs = int.parse(options.option('gap-ms')!);
    final proxy = options.option('proxy');
    final route = proxy == null
        ? const DirectRoute()
        : HttpProxyRoute(proxy.split(':').first, int.parse(proxy.split(':').last));
    final policy = FixedProxyPolicy(global: route);
    final http = IoLiveHttp(proxy: policy);
    final site = factory?.call(http);
    final agent = options.option('user-agent');
    final urlRooms = address == null ? null : UrlRecordRooms(address, headers: {'user-agent': ?agent});
    final out = options.option('out') ?? (await Directory.systemTemp.createTemp('live_cli_record')).path;
    final remux = options.flag('remux');
    final wall = Stopwatch()..start();
    void log(String text) =>
        stdout.writeln('[${(wall.elapsedMilliseconds / 1000).toStringAsFixed(1).padLeft(6)} s] $text');

    RecordManager? manager;
    try {
      final ref = urlRooms?.ref ?? await (site! as LinkResolver).resolve(input);
      if (ref == null) {
        stderr.writeln('Not a $platform room: $input');
        return 1;
      }
      final detail = urlRooms != null ? await urlRooms.detail(ref) : await (site! as RoomSource).detail(ref);
      log('room     ${ref.key} · ${detail.card.state.name} · ${detail.card.anchorName} · ${detail.card.title}');
      if (detail.card.state == LiveState.offline) {
        log('stopped  the room is not live');
        return 2;
      }
      final quality = options.option('quality');
      final format = options.option('format');
      final rooms = _LoggingRooms(
        urlRooms ?? SiteRecordRooms((id) => id == platform ? site : null),
        log,
        format: format == null ? null : StreamFormat.values.byName(format),
        lineId: options.option('line'),
        renewAfter: options.option('renew-after') == null
            ? null
            : Duration(seconds: int.parse(options.option('renew-after')!)),
      );
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
        remuxer: !remux
            ? null
            : options.option('remuxer') == 'ffmpeg'
            ? const FfmpegProcessRemuxer()
            : const Mp4Remuxer(),
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
        if (!path.endsWith('.flv')) {
          clean = await _checkHlsSegment(path) && clean;
          continue;
        }
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
        final boxes = [for (final box in await topLevelBoxes(path)) box.type];
        final faststart = boxes.contains('moov') && boxes.indexOf('moov') < boxes.indexOf('mdat');
        stdout.writeln(
          '  mp4             ${p.basename(path)} · ${boxes.join(' ')}'
          '${steps == null ? '' : ' · ${steps.count} packets, max DTS step ${(steps.maxStep * 1000).round()} ms, '
                    '${steps.backwards} backwards'}',
        );
        clean = clean && faststart && (steps == null || steps.backwards == 0);
      }
      for (final path in session.outputs) {
        final media = await checkMedia(path);
        if (media == null) continue;
        stdout.writeln(
          '    decode        ${media.decodeErrors.isEmpty ? 'clean' : media.decodeErrors.split('\n').take(3).join(' | ')}',
        );
        clean = clean && media.decodeErrors.isEmpty;
      }
      final gapsFile = File(session.layout.gaps);
      if (gapsFile.existsSync()) {
        final gaps = (jsonDecode(gapsFile.readAsStringSync()) as Map<String, Object?>)['gaps']! as List<Object?>;
        stdout.writeln('  gaps.json       ${gaps.length} entries');
        for (final gap in gaps.take(10)) {
          stdout.writeln('    $gap');
        }
        clean = clean && gaps.length <= int.parse(options.option('max-gaps')!);
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

/// Checks one HLS segment file (`.ts` or `.m4s`) with ffprobe and a full
/// decode; prints the result and returns whether it is clean.
Future<bool> _checkHlsSegment(String path) async {
  stdout.writeln(
    '  segment         ${p.basename(path)} · ${(File(path).lengthSync() / 1048576).toStringAsFixed(1)} MiB',
  );
  final media = await checkMedia(path);
  if (media == null) {
    stdout.writeln('    check         skipped (ffprobe/ffmpeg not installed)');
    return true;
  }
  for (final type in const ['video', 'audio']) {
    final packets = media.packets[type];
    if (packets == null) continue;
    final label = '    $type'.padRight(18);
    stdout.writeln(
      '$label${media.codecs[type]} $packets packets, ${media.durations[type]?.toStringAsFixed(3)} s, '
      'DTS backwards ${media.backwards[type] ?? 0}',
    );
  }
  stdout.writeln(
    '    decode        ${media.decodeErrors.isEmpty ? 'clean' : media.decodeErrors.split('\n').take(3).join(' | ')}',
  );
  return media.decodeErrors.isEmpty;
}
