import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:live_cli/src/probe/sites.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';

/// Timestamp continuity of a relayed FLV, fed one packet at a time.
final class LeaseReport {
  /// Creates a report; a step between consecutive video or audio tags larger
  /// than [gapMs] counts as a gap.
  new({this.gapMs = 500});

  /// Gap threshold.
  final int gapMs;

  /// Video timestamps in arrival order.
  final List<int> video = [];

  /// Audio timestamp count.
  int audioTags = 0;

  /// Script tags seen.
  int scripts = 0;

  /// Video tags whose timestamp went back.
  int videoBackwards = 0;

  /// Audio tags whose timestamp did not advance.
  int audioBackwards = 0;

  /// Gaps found, as (stream, from, to).
  final List<({String stream, int from, int to})> gaps = [];

  int? _lastAudio;

  /// Largest step between video tags.
  int maxVideoStep = 0;

  /// Largest step between audio tags.
  int maxAudioStep = 0;

  /// Adds one packet (the FLV header is ignored).
  void add(Uint8List packet) {
    if (packet.length < FlvTag.headerLength || packet[0] == 0x46) return;
    final type = FlvTag.type(packet);
    final ts = FlvTag.timestamp(packet);
    if (type == FlvTag.script) {
      scripts++;
      return;
    }
    if (FlvTag.isVideoConfig(packet) || FlvTag.isAudioConfig(packet)) return;
    if (type == FlvTag.video) {
      if (video.isNotEmpty) {
        final step = ts - video.last;
        if (step < 0) videoBackwards++;
        if (step > maxVideoStep) maxVideoStep = step;
        if (step > gapMs) gaps.add((stream: 'video', from: video.last, to: ts));
      }
      video.add(ts);
    } else if (type == FlvTag.audio) {
      audioTags++;
      final last = _lastAudio;
      if (last != null) {
        final step = ts - last;
        if (step <= 0) audioBackwards++;
        if (step > maxAudioStep) maxAudioStep = step;
        if (step > gapMs) gaps.add((stream: 'audio', from: last, to: ts));
      }
      _lastAudio = ts;
    }
  }

  /// Media time covered by video.
  Duration get videoSpan => video.length < 2 ? Duration.zero : Duration(milliseconds: video.last - video.first);

  /// The largest video step within [window] ms of [at] (a splice point).
  int stepAround(int at, {int window = 2000}) {
    var step = 0;
    for (var i = 1; i < video.length; i++) {
      if ((video[i] - at).abs() > window) continue;
      final delta = video[i] - video[i - 1];
      if (delta > step) step = delta;
    }
    return step;
  }

  /// Whether the stream stayed continuous.
  bool get clean => gaps.isEmpty && videoBackwards == 0 && audioBackwards == 0;
}

/// `live_cli lease <platform> <room>`: plays a line whose lease cuts the
/// connection through the v4 loopback relay for a while and reports whether
/// the spliced output kept one gapless timestamp timeline across renewals
/// (spec/modules/playback.md SRC-5 【探针】).
class LeaseCommand extends Command<int> {
  /// Creates the command.
  new() {
    argParser
      ..addOption('duration', defaultsTo: '420', help: 'Seconds to follow the stream.')
      ..addOption('proxy', help: 'host:port of an HTTP proxy for this platform; direct by default.')
      ..addOption('quality', help: 'Quality id to request; the best offered by default.')
      ..addOption('line', help: 'Line id to follow; the first line by default.')
      ..addOption('gap-ms', defaultsTo: '500', help: 'A timestamp step above this counts as a gap.');
  }

  @override
  String get name => 'lease';

  @override
  String get description => 'Follow a leased stream across renewals and report timestamp gaps.';

  @override
  String get invocation => 'live_cli lease <platform> <room id or link> [options]';

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
    final clock = Stopwatch()..start();
    void log(String text) =>
        stdout.writeln('[${(clock.elapsedMilliseconds / 1000).toStringAsFixed(1).padLeft(6)} s] $text');

    LoopbackRelay? relay;
    try {
      final ref = await (site as LinkResolver).resolve(input);
      if (ref == null) {
        stderr.writeln('Not a $platform room: $input');
        return 1;
      }
      final detail = await (site as RoomSource).detail(ref);
      log('room     ${ref.key} · ${detail.card.state.name} · ${detail.card.anchorName} · ${detail.card.title}');
      if (detail.card.state != LiveState.live) {
        log('stopped  the room is not live');
        return 2;
      }
      final streams = site as StreamSource;
      final wanted = options.option('quality');
      final set = await streams.streams(
        detail,
        quality: wanted == null ? null : Quality(id: wanted, label: wanted, rank: 0),
      );
      final lineId = options.option('line');
      final line = set.lines.where((line) => lineId == null || line.lineId == lineId).firstOrNull;
      if (line == null) {
        log('stopped  no line ${lineId ?? ''} (have ${set.lines.map((line) => line.lineId).join(', ')})');
        return 2;
      }
      final lease = line.lease;
      log(
        'line     ${line.lineId} ${line.format.name} ${line.effective.label}'
        '${lease == null ? ' · no lease' : ' · refresh ${lease.refreshAt.toLocal()} · cuts=${lease.cutsConnection}'}',
      );
      if (PipelineMode.of(line, canRenew: true) != PipelineMode.splice) {
        log('stopped  this line is not spliced (only FLV whose lease cuts the connection is)');
        return 2;
      }

      relay = await LoopbackRelay.start(proxy: policy);
      var renewals = 0;
      final switches = <SpliceSwitched>[];
      final relayed = relay.openSplice(
        line,
        site: platform,
        renew: (current) async {
          renewals++;
          final renewed = await streams.streams(detail, quality: current.requested);
          final next =
              renewed.lines.where((candidate) => candidate.lineId == current.lineId).firstOrNull ?? renewed.lines.first;
          log('renew    #$renewals → ${next.lineId} · next refresh ${next.lease?.refreshAt.toLocal()}');
          return next;
        },
        onEvent: (event) {
          if (event is SpliceSwitched) switches.add(event);
          log('splice   $event');
        },
      );

      final report = LeaseReport(gapMs: gapMs);
      final ended = await _follow(relayed.uri, duration, report, (elapsed) {
        log(
          'progress ${report.videoSpan.inSeconds} s of video · ${report.video.length} video / ${report.audioTags} audio '
          'tags · ${switches.length} switches · max step v${report.maxVideoStep}/a${report.maxAudioStep} ms · '
          '${report.gaps.length} gaps',
        );
      });
      await relayed.close();

      final wall = clock.elapsed;
      stdout
        ..writeln()
        ..writeln('lease report · $platform ${ref.roomId} · line ${line.lineId}')
        ..writeln('  followed        ${wall.inSeconds} s wall, ${report.videoSpan.inSeconds} s of video')
        ..writeln('  output          ${ended ?? 'still streaming at the end'}')
        ..writeln('  renewals        $renewals requested, ${switches.length} spliced')
        ..writeln('  tags            ${report.video.length} video, ${report.audioTags} audio, ${report.scripts} script')
        ..writeln('  max step        video ${report.maxVideoStep} ms, audio ${report.maxAudioStep} ms')
        ..writeln('  backwards       video ${report.videoBackwards}, audio ${report.audioBackwards}')
        ..writeln('  gaps > $gapMs ms  ${report.gaps.length}');
      for (final gap in report.gaps.take(20)) {
        stdout.writeln('    ${gap.stream} ${gap.from} → ${gap.to} (${gap.to - gap.from} ms)');
      }
      for (final switched in switches) {
        stdout.writeln(
          '  switch at ${switched.switchAt} ms: largest video step nearby ${report.stepAround(switched.switchAt)} ms'
          '${switched.shifted ? ', shifted timeline' : ''}${switched.oldEnded ? ', after the old connection ended' : ''}',
        );
      }
      final needsSwitch = lease != null && DateTime.now().isAfter(lease.refreshAt.add(const Duration(seconds: 30)));
      final passed = report.clean && ended == null && (!needsSwitch || switches.isNotEmpty);
      stdout.writeln('  result          ${passed ? 'PASS' : 'FAIL'}');
      return passed ? 0 : 1;
    } on SiteError catch (error) {
      log('failed   $error');
      return 2;
    } finally {
      await relay?.close();
      http.close();
    }
  }

  /// Reads the relay output for [duration]; returns why it ended early, or null.
  Future<String?> _follow(Uri uri, Duration duration, LeaseReport report, void Function(Duration) progress) async {
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    final framer = FlvFramer();
    final watch = Stopwatch()..start();
    final ticker = Timer.periodic(const Duration(seconds: 30), (_) => progress(watch.elapsed));
    try {
      final response = await (await client.getUrl(uri)).close();
      if (response.statusCode != HttpStatus.ok) return 'relay answered HTTP ${response.statusCode}';
      final done = Completer<String?>();
      final subscription = response.listen(
        (chunk) {
          try {
            framer.add(chunk).forEach(report.add);
          } on FormatException catch (error) {
            if (!done.isCompleted) done.complete('bad FLV: $error');
          }
        },
        onDone: () {
          if (!done.isCompleted) done.complete('relay output ended');
        },
        onError: (Object error) {
          if (!done.isCompleted) done.complete('relay output failed: $error');
        },
      );
      final ended = await done.future.timeout(duration, onTimeout: () => null);
      await subscription.cancel();
      return ended;
    } finally {
      ticker.cancel();
      client.close(force: true);
    }
  }
}
