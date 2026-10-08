import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:live_cli/src/patrol/checks.dart';
import 'package:live_cli/src/patrol/media.dart';
import 'package:live_cli/src/patrol/report.dart';
import 'package:live_cli/src/sites.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';

/// `live_cli probe <platform> <room id or link>`: one room from link to the
/// first media bytes over the real network (the archived probe, on the
/// current `LiveSite`). Addresses are printed redacted.
final class ProbeCommand extends Command<int> {
  /// Creates the command.
  new() {
    argParser
      ..addOption('proxy', help: 'host:port of an HTTP proxy for this platform; direct by default.')
      ..addOption('quality', help: 'Quality name to request; the first offered by default.')
      ..addFlag('media', defaultsTo: true, help: 'Read the first 64 KiB of every line and check the container.');
  }

  @override
  String get name => 'probe';

  @override
  String get description => 'Resolve one room through its adapter and read the first bytes of its lines.';

  @override
  String get invocation => 'live_cli probe <platform> <room id or link> [options]';

  @override
  Future<int> run() async {
    final options = argResults!;
    if (options.rest.length != 2) usageException('Expected <platform> <room id or link>.');
    final [platform, input] = options.rest;
    final factories = siteFactories();
    final factory = factories[platform.trim().toLowerCase()];
    if (factory == null) usageException('Unknown platform "$platform" (have: ${factories.keys.join(', ')}).');
    final HttpProxyRoute? route;
    try {
      route = switch (options.option('proxy')) {
        final String value => parseProxy(value),
        null => null,
      };
    } on FormatException catch (error) {
      usageException(error.message);
    }
    final policy = FixedProxyPolicy(global: route ?? const DirectRoute());
    final http = IoLiveHttp(proxy: policy);
    final site = factory(http, policy);
    final clock = Stopwatch()..start();
    void step(String text) => stdout.writeln('[${clock.elapsedMilliseconds.toString().padLeft(6)} ms] ${scrub(text)}');
    try {
      var roomId = input;
      if (input.contains('://') || input.startsWith('www.')) {
        final link = await LinkParser(SiteRegistry({site.id: () => site}), http).parse(input);
        if (link == null) {
          stderr.writeln('Not a ${site.id} room: $input');
          return 1;
        }
        roomId = link.roomId;
        step('link     $roomId');
      }
      final detail = await site.getRoomDetail(roomId: roomId);
      step(
        'detail   ${detail.effectiveLiveStatus.name} · ${detail.nick} · ${detail.title} · '
        '${detail.area ?? '-'} · ${detail.watching}',
      );
      if (!detail.isPlayableNow) {
        step('streams  skipped: room is ${detail.effectiveLiveStatus.name}');
        return 0;
      }
      final qualities = await site.discoverPlayQualities(detail: detail);
      step('quality  ${qualities.map((quality) => '${quality.selectionId}:${quality.quality}').join(' ')}');
      if (qualities.isEmpty) return 1;
      final wanted = options.option('quality');
      final quality = qualities.firstWhere((quality) => quality.quality == wanted, orElse: () => qualities.first);
      final resolution = await site.resolvePlayUrls(detail: detail, quality: quality);
      step(
        'resolve  ${quality.quality} · applied ${resolution.appliedQualityData ?? '?'} · '
        '${resolution.inputRecipe != null ? 'recipe (not opened)' : '${resolution.lines.length} lines'}',
      );
      var failed = false;
      for (final line in resolution.lines) {
        final url = Uri.parse(line.url);
        final lease = line.lease;
        final leaseText = lease == null ? '' : ' · refresh ${lease.refreshAt.toUtc().toIso8601String()}';
        if (!options.flag('media')) {
          step('  line ${redact(url)} ${line.format?.name ?? '?'} ${line.codec ?? '?'}$leaseText');
          continue;
        }
        final answer = await head(http, site.id, url, line.headers);
        final found = container(answer.bytes);
        final ok = answer.ok && containerMatches(line.format, url, found);
        failed |= !ok;
        step(
          '  line ${redact(url)} ${line.format?.name ?? '?'} ${line.codec ?? '?'} · HTTP ${answer.status} · '
          '${answer.bytes.length} bytes · ${found.label}${ok ? '' : ' · MISMATCH'}$leaseText',
        );
      }
      return failed ? 1 : 0;
    } on Object catch (error) {
      step('failed   ${describeError(error)}');
      return 1;
    } finally {
      http.close();
    }
  }
}
