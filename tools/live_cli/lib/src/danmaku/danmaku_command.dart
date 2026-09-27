import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:live_cli/src/danmaku/recorder.dart';
import 'package:live_cli/src/probe/sites.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';

/// `live_cli danmaku <platform> <room>`: joins a room's chat through the v4
/// connector and prints decoded messages; `--record <case>` also writes the
/// scrubbed frames to `fixtures/<platform>/danmaku/<case>/`.
class DanmakuCommand extends Command<int> {
  /// Creates the command.
  new() {
    argParser
      ..addOption('proxy', help: 'host:port of an HTTP proxy for this platform; direct by default.')
      ..addOption('seconds', defaultsTo: '30', help: 'How long to listen.')
      ..addOption('record', help: 'Case name: save scrubbed frames to fixtures/<platform>/danmaku/<case>/.')
      ..addOption('root', defaultsTo: '.', help: 'Repository root for --record.')
      ..addOption('dump', help: 'Also write the unscrubbed frames to this local file (debugging; never commit it).')
      ..addOption('cookie-file', help: 'File holding the platform cookie (kept out of argv and never recorded).')
      ..addFlag('recommended', negatable: false, help: 'Ignore <room>; use the busiest live recommended room.')
      ..addOption('pick', defaultsTo: '0', help: 'With --recommended: the n-th busiest room (0 is the busiest).')
      ..addFlag('pipeline', help: 'Print filtered batches instead of raw events.', negatable: false);
  }

  @override
  String get name => 'danmaku';

  @override
  String get description => 'Connect to a room chat and print decoded messages.';

  @override
  String get invocation => 'live_cli danmaku <platform> <room id or link> [options]';

  @override
  Future<int> run() async {
    final options = argResults!;
    final recommended = options.flag('recommended');
    if (options.rest.length != (recommended ? 1 : 2)) usageException('Expected <platform> <room id or link>.');
    final platform = options.rest.first;
    final factory = siteFactories[platform];
    if (factory == null) usageException('No v4 adapter for "$platform".');
    final proxy = options.option('proxy');
    final route = proxy == null
        ? const DirectRoute()
        : HttpProxyRoute(proxy.split(':').first, int.parse(proxy.split(':').last));
    final policy = FixedProxyPolicy(global: route);
    final http = IoLiveHttp(proxy: policy);
    final vault = MemoryCookieVault();
    final cookieFile = options.option('cookie-file');
    if (cookieFile != null) vault.set(platform, File(cookieFile).readAsStringSync().trim());
    final site = factory(http);
    final seconds = int.parse(options.option('seconds')!);
    final clock = Stopwatch()..start();
    void step(String text) => stdout.writeln('[${clock.elapsedMilliseconds.toString().padLeft(6)} ms] $text');
    try {
      final RoomRef ref;
      if (recommended) {
        final page = await (site as CatalogSource).recommended();
        final live = page.items.where((card) => card.state == LiveState.live).toList();
        if (live.isEmpty) {
          stderr.writeln('No live recommended room.');
          return 1;
        }
        int audience(RoomCard card) =>
            card.audience.online ?? card.audience.popularity ?? card.audience.cumulative ?? 0;
        live.sort((a, b) => audience(b).compareTo(audience(a)));
        ref = live[int.parse(options.option('pick')!).clamp(0, live.length - 1)].ref;
      } else {
        final resolved = await (site as LinkResolver).resolve(options.rest[1]);
        if (resolved == null) {
          stderr.writeln('Not a $platform room: ${options.rest[1]}');
          return 1;
        }
        ref = resolved;
      }
      final detail = await (site as RoomSource).detail(ref);
      step('room     ${detail.ref.key} · ${detail.card.state.name} · ${detail.card.anchorName} · ${detail.card.title}');
      final recordCase = options.option('record');
      final dump = options.option('dump');
      final recorder = recordCase == null && dump == null ? null : FrameRecorder(platform: platform, detail: detail);
      final DanmakuTransport base = IoDanmakuTransport(proxy: policy, http: http);
      final transport = recorder == null ? base : recorder.wrap(base);
      final credentials = SiteDanmakuCredentials(
        bilibiliSite: site is BilibiliSite ? site : null,
        douyinSite: site is DouyinSite ? site : null,
        cookies: vault,
      );
      if (options.flag('pipeline')) {
        return await _viaWorker(detail, policy, credentials, Duration(seconds: seconds), step);
      }
      final connector = danmakuConnectorFor(detail, transport: transport, credentials: credentials);
      if (connector == null) {
        step('unsupported: $platform has no chat connector');
        return 2;
      }
      var chats = 0;
      final subscription = connector.events.listen((event) {
        if (event is DanmakuChat) chats++;
        step(_line(event));
      });
      final joined = await connector.connect().timeout(const Duration(seconds: 20), onTimeout: () => false);
      if (!joined) step('not joined within 20 s');
      await Future<void>.delayed(Duration(seconds: seconds));
      await connector.close();
      await subscription.cancel();
      step('done     $chats chat messages');
      if (dump != null) recorder?.dumpRaw(dump);
      if (recorder != null && recordCase != null) {
        final directory = await recorder.write(root: options.option('root')!, name: recordCase, route: route);
        step('recorded ${recorder.frameCount} frames to $directory');
      }
      return joined && chats > 0 ? 0 : 3;
    } on SiteError catch (error) {
      step('failed   $error');
      return 2;
    } finally {
      http.close();
    }
  }

  /// Runs the room through [DanmakuWorker] (background isolate, filters,
  /// sampling, 64 ms batches) and prints one line per batch.
  static Future<int> _viaWorker(
    RoomDetail detail,
    ProxyPolicy policy,
    DanmakuCredentials credentials,
    Duration listen,
    void Function(String) step,
  ) async {
    final worker = await DanmakuWorker.spawn(proxy: policy, credentials: credentials);
    final session = worker.open(detail);
    var batches = 0;
    var chats = 0;
    final subscription = session.batches.listen((batch) {
      batches++;
      chats += batch.list.length;
      step(
        'batch    list ${batch.list.length} screen ${batch.screen.length} gifts ${batch.gifts.length} '
        'sc ${batch.superChats.length} dropped ${batch.dropped}'
        '${batch.online.isEmpty ? '' : ' online ${batch.online.entries.map((e) => '${e.key.name}=${e.value}').join(',')}'}'
        '${batch.system.isEmpty ? '' : ' system ${batch.system.map((s) => s.status.name).join(',')}'}',
      );
    });
    await Future<void>.delayed(listen);
    await session.close();
    await subscription.cancel();
    await worker.dispose();
    step('done     $batches batches, $chats list messages');
    return chats > 0 ? 0 : 3;
  }

  static String _line(DanmakuEvent event) => switch (event) {
    DanmakuChat(:final userName, :final text, :final id, :final color, :final suspectedBot) =>
      'chat     $userName: $text${id == null ? '' : '  [$id]'}'
          '${color == DanmakuColors.white ? '' : ' #${color.toRadixString(16).padLeft(6, '0')}'}'
          '${suspectedBot ? ' (bot?)' : ''}',
    DanmakuGift(:final userName, :final giftName, :final count) => 'gift     $userName: $giftName x$count',
    DanmakuSuperChat(:final userName, :final price, :final text) => 'sc       $userName ¥$price: $text',
    DanmakuOnline(:final audience, :final value) => 'online   ${audience.name} $value',
    DanmakuSystem(:final status, :final args) => 'status   ${status.name} ${args.join(' ')}',
  };
}
