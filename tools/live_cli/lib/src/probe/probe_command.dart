import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:live_cli/src/probe/sites.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';

/// `live_cli probe <platform> <room or link>`: resolve, detail, streams and
/// the first media bytes over the real network (PLAN phase 4 exit check).
class ProbeCommand extends Command<int> {
  /// Creates the command.
  new() {
    argParser
      ..addOption('proxy', help: 'host:port of an HTTP proxy for this platform; direct by default.')
      ..addOption('quality', help: 'Quality id to request; the best offered by default.')
      ..addFlag('media', defaultsTo: true, help: 'Read the first 64 KiB of the first line and check the container.');
  }

  @override
  String get name => 'probe';

  @override
  String get description => 'Resolve a room through its v4 adapter and read the first media bytes.';

  @override
  String get invocation => 'live_cli probe <platform> <room id or link> [options]';

  @override
  Future<int> run() async {
    final options = argResults!;
    if (options.rest.length != 2) usageException('Expected <platform> <room id or link>.');
    final [platform, input] = options.rest;
    final factory = siteFactories[platform];
    if (factory == null) usageException('No v4 adapter for "$platform" yet (have: ${siteFactories.keys.join(', ')}).');
    final proxy = options.option('proxy');
    final route = proxy == null
        ? const DirectRoute()
        : HttpProxyRoute(proxy.split(':').first, int.parse(proxy.split(':').last));
    final http = IoLiveHttp(proxy: FixedProxyPolicy(global: route));
    final site = factory(http);
    final clock = Stopwatch()..start();
    void step(String text) => stdout.writeln('[${clock.elapsedMilliseconds.toString().padLeft(5)} ms] $text');
    try {
      final ref = await (site as LinkResolver).resolve(input);
      if (ref == null) {
        stderr.writeln('Not a $platform room: $input');
        return 1;
      }
      step('resolve  ${ref.key}');
      final detail = await (site as RoomSource).detail(ref);
      final card = detail.card;
      step('detail   ${card.state.name} · ${card.anchorName} · ${card.title} · ${card.audience}');
      if (card.state != LiveState.live) {
        step('streams  skipped: room is ${card.state.name}');
        return 0;
      }
      final wanted = options.option('quality');
      final set = await (site as StreamSource).streams(
        detail,
        quality: wanted == null ? null : Quality(id: wanted, label: wanted, rank: 0),
      );
      step('streams  ${set.qualities.map((q) => '${q.id}:${q.label}').join(' ')} · selected ${set.selected.label}');
      for (final line in set.lines) {
        final lease = line.lease;
        step(
          '  line ${line.lineId} ${line.format.name} ${line.codec ?? '?'} effective ${line.effective.label}'
          '${line.confirmed == null ? ' (unconfirmed)' : ''}'
          '${lease == null ? '' : ' · refresh ${lease.refreshAt.toUtc().toIso8601String()} cuts=${lease.cutsConnection}'}',
        );
      }
      if (options.flag('media') && set.lines.isNotEmpty) {
        final line = set.lines.first;
        final media = await _head(route, line.url, line.headers);
        step('media    HTTP ${media.status} · ${media.bytes.length} bytes · ${_container(media.bytes)}');
        if (media.status < 200 || media.status >= 300 || _container(media.bytes) == 'unknown') return 3;
        if (line.hlsRelay != null) {
          final relayed = await _throughRelay(route, platform, line);
          step(
            'relay    ${relayed.what} · HTTP ${relayed.status} · ${relayed.bytes.length} bytes · ${_container(relayed.bytes)}',
          );
          if (relayed.status != 200 || !const {'MPEG-TS', 'fMP4'}.contains(_container(relayed.bytes))) return 3;
        }
      }
      return 0;
    } on SiteError catch (error) {
      step('failed   $error');
      return 2;
    } finally {
      if (site is Fc2LiveSite) await site.close();
      if (site is NiconicoSite) await site.close();
      http.close();
    }
  }

  /// The first segment (or the fMP4 init map) of a line that needs the HLS
  /// relay, fetched through the relay as the player would (ADR 0033): the
  /// relay adds the per-path cookies and restores scrambled segments, so an
  /// MPEG-TS segment starts with the sync byte again.
  Future<({String what, int status, List<int> bytes})> _throughRelay(
    ProxyRoute route,
    String platform,
    StreamLine line,
  ) async {
    final relay = await LoopbackRelay.start(proxy: FixedProxyPolicy(global: route));
    try {
      final input = relay.openHls(line, site: platform);
      Future<String?> playlist(Uri url) async {
        final answer = await _head(const DirectRoute(), url, const {}, limit: 1 << 22);
        return answer.status == 200 ? utf8.decode(answer.bytes, allowMalformed: true) : null;
      }

      var text = await playlist(input.uri);
      if (text == null) return (what: 'playlist', status: 0, bytes: const <int>[]);
      String? firstUri(String text) => const LineSplitter()
          .convert(text)
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .firstOrNull;
      if (text.contains('#EXT-X-STREAM-INF')) {
        final variant = firstUri(text);
        text = variant == null ? null : await playlist(Uri.parse(variant));
        if (text == null) return (what: 'variant', status: 0, bytes: const <int>[]);
      }
      final map = RegExp('#EXT-X-MAP:.*URI="([^"]+)"').firstMatch(text)?.group(1);
      final target = map ?? firstUri(text);
      if (target == null) return (what: 'segment', status: 0, bytes: const <int>[]);
      final answer = await _head(const DirectRoute(), Uri.parse(target), const {});
      return (what: map == null ? 'first segment' : 'init map', status: answer.status, bytes: answer.bytes);
    } finally {
      await relay.close();
    }
  }

  /// Reads the first [limit] bytes of [url] (64 KiB) and drops the
  /// connection; live media never ends, so this streams instead of going
  /// through LiveHttp.
  Future<({int status, List<int> bytes})> _head(
    ProxyRoute route,
    Uri url,
    Map<String, String> headers, {
    int limit = 65536,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..findProxy = (_) => route.directive;
    try {
      final request = await client.getUrl(url);
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(const Duration(seconds: 10));
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        bytes.addAll(chunk);
        if (bytes.length >= limit) break;
      }
      return (status: response.statusCode, bytes: bytes);
    } on Object catch (error) {
      stderr.writeln('media read failed: $error');
      return (status: 0, bytes: const <int>[]);
    } finally {
      client.close(force: true);
    }
  }

  static String _container(List<int> bytes) {
    if (bytes.length >= 3 && bytes[0] == 0x46 && bytes[1] == 0x4C && bytes[2] == 0x56) return 'FLV';
    if (bytes.length >= 7 && String.fromCharCodes(bytes.take(7)) == '#EXTM3U') return 'HLS playlist';
    if (bytes.isNotEmpty && bytes[0] == 0x47) return 'MPEG-TS';
    if (bytes.length >= 8 && String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') return 'fMP4';
    return 'unknown';
  }
}
