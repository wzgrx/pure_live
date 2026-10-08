import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:live_cli/src/patrol/checks.dart';
import 'package:live_cli/src/patrol/danmaku.dart';
import 'package:live_cli/src/patrol/media.dart';
import 'package:live_cli/src/patrol/report.dart';
import 'package:live_cli/src/patrol/result.dart';
import 'package:live_cli/src/patrol/targets.dart';
import 'package:live_cli/src/sites.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// What `live_cli patrol` was asked to do.
@immutable
final class PatrolOptions {
  /// Creates the options.
  new({required List<PatrolTarget> targets, this.proxy, this.danmakuSeconds = 0, this.out, this.json})
    : targets = List.unmodifiable(targets);

  /// Platforms, in `SiteIds.supported` order.
  final List<PatrolTarget> targets;

  /// The proxy of the overseas platforms, or null.
  final HttpProxyRoute? proxy;

  /// P13 seconds; 0 skips it.
  final int danmakuSeconds;

  /// Markdown report path, or null.
  final String? out;

  /// JSON report path, or null.
  final String? json;
}

/// The options of `patrol`.
void addPatrolOptions(ArgParser parser) {
  parser
    ..addFlag('domestic', negatable: false, help: 'The 18 domestic platforms (direct).')
    ..addFlag('overseas', negatable: false, help: 'The 16 overseas platforms (through --proxy).')
    ..addFlag('all', negatable: false, help: 'All 34 platforms.')
    ..addOption('proxy', help: 'host:port of the HTTP proxy for overseas platforms; domestic ones stay direct.')
    ..addOption('danmaku', defaultsTo: '0', help: "Seconds to listen to one live room's danmaku per platform (P13).")
    ..addOption('out', help: 'Write the Markdown report here.')
    ..addOption('json', help: 'Write the JSON results here.');
}

/// Reads [results]; throws [FormatException] for bad arguments (exit 64).
PatrolOptions parsePatrolOptions(ArgResults results) {
  final selected = <String>{};
  if (results.flag('all') || results.flag('domestic')) selected.addAll(domesticTargets.map((target) => target.site));
  if (results.flag('all') || results.flag('overseas')) selected.addAll(overseasTargets.map((target) => target.site));
  for (final name in results.rest) {
    final target = targetOf(name);
    if (target == null) {
      throw FormatException('Unknown platform "$name" (have: ${patrolTargets.map((t) => t.site).join(', ')})');
    }
    selected.add(target.site);
  }
  if (selected.isEmpty) throw const FormatException('Name platforms, or pass --domestic, --overseas or --all');
  final danmaku = int.tryParse(results.option('danmaku') ?? '0');
  if (danmaku == null || danmaku < 0) throw const FormatException('--danmaku takes a number of seconds');
  final proxy = switch (results.option('proxy')) {
    final String value => parseProxy(value),
    null => null,
  };
  return PatrolOptions(
    targets: [
      for (final target in patrolTargets)
        if (selected.contains(target.site)) target,
    ],
    proxy: proxy,
    danmakuSeconds: danmaku,
    out: results.option('out'),
    json: results.option('json'),
  );
}

/// Runs a patrol of [options] and returns the report. Overseas platforms
/// without a proxy are "没测到：没有代理"; domestic ones are always direct.
/// The seams ([factories], [httpFor], [media], [links], [danmaku]) let the
/// tests run it on fakes without any network (D-017).
Future<PatrolReport> runPatrol(
  PatrolOptions options, {
  Map<String, SiteFactory>? factories,
  LiveHttp Function(ProxyPolicy policy)? httpFor,
  MediaReader Function(LiveHttp http)? media,
  LinkReader Function(LiveHttp http)? links,
  DanmakuProbe Function(LiveHttp http, ProxyPolicy policy, String site)? danmaku,
  DateTime Function()? now,
  void Function(String line)? log,
}) async {
  final clock = now ?? DateTime.now;
  final build = factories ?? siteFactories();
  final policy = patrolProxyPolicy(
    overseas: overseasTargets.map((target) => target.site),
    overseasProxy: options.proxy,
  );
  final transport = (httpFor ?? (policy) => IoLiveHttp(proxy: policy))(policy);
  final readMedia = (media ?? _realMedia)(transport);
  final readLink = (links ?? _realLinks)(transport);
  final startedAt = clock();
  final runs = <SiteRun>[];
  try {
    for (final target in options.targets) {
      if (target.overseas && options.proxy == null) {
        runs.add(PlatformPatrol.notReached(target, '没有代理（加 --proxy host:port）'));
        log?.call('${target.name}: 没有代理，跳过');
        continue;
      }
      final factory = build[target.site];
      if (factory == null) {
        runs.add(PlatformPatrol.notReached(target, '工具没有这个平台的适配器', network: '—'));
        continue;
      }
      log?.call('${target.name}: 开始');
      final http = target.interval > Duration.zero
          ? ThrottledHttp(transport, minIntervals: {target.site: target.interval})
          : transport;
      final site = factory(http, policy);
      final probe = options.danmakuSeconds > 0 && danmakuFactories.containsKey(target.site)
          ? (danmaku ?? _realDanmaku)(http, policy, target.site)
          : null;
      final run = await PlatformPatrol(
        site: site,
        target: target,
        media: readMedia,
        links: readLink,
        danmaku: probe,
        danmakuDuration: Duration(seconds: options.danmakuSeconds),
        network: target.overseas ? '代理' : '直连',
        now: clock,
      ).run();
      runs.add(run);
      log?.call(
        [
          '${target.name}: 正常 ${run.count(Outcome.ok)}',
          '失败 ${run.count(Outcome.failed)}',
          '没测到 ${run.count(Outcome.notRun)}',
          '不支持 ${run.count(Outcome.unsupported)}（${formatDuration(run.elapsed)}）',
        ].join('、'),
      );
    }
  } finally {
    transport.close();
  }
  return PatrolReport(
    startedAt: startedAt,
    finishedAt: clock(),
    proxied: options.proxy != null,
    danmakuSeconds: options.danmakuSeconds,
    sites: runs,
  );
}

MediaReader _realMedia(LiveHttp http) =>
    (site, line) => head(http, site, Uri.parse(line.url), line.headers);

LinkReader _realLinks(LiveHttp http) => (site, url) async {
  final parser = LinkParser(SiteRegistry({site.id: () => site}), http);
  return (await parser.parse(url, timeout: const Duration(seconds: 20)))?.roomId;
};

DanmakuProbe _realDanmaku(LiveHttp http, ProxyPolicy policy, String id) =>
    (site, room, duration) => sampleDanmaku(danmakuFactories[id]!(http, policy, site), room.danmakuData, duration);

/// `live_cli patrol`: runs the checks of CHECKS.md against the real
/// platforms. By hand only; never part of the gate or the tests (D-017).
final class PatrolCommand extends Command<int> {
  /// Creates the command.
  new() {
    addPatrolOptions(argParser);
  }

  @override
  String get name => 'patrol';

  @override
  String get description =>
      'Run checks P1-P13 (docs/E-直播平台/E07-平台巡检/CHECKS.md) against real platforms and write a report.';

  @override
  String get invocation => 'live_cli patrol [<platform> ...] [--domestic] [--overseas] [--all] [options]';

  @override
  Future<int> run() async {
    final PatrolOptions options;
    try {
      options = parsePatrolOptions(argResults!);
    } on FormatException catch (error) {
      usageException(error.message);
    }
    final report = await runPatrol(options, log: stderr.writeln);
    final markdown = markdownReport(report);
    if (options.out case final path?) await writeReport(path, markdown);
    if (options.json case final path?) await writeReport(path, '${jsonReport(report)}\n');
    stdout.write(markdown);
    return report.hasFailure ? 1 : 0;
  }
}
