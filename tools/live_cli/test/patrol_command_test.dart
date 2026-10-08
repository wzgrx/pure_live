import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:live_cli/live_cli.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

import 'fakes.dart';

PatrolOptions _parse(List<String> arguments) {
  final parser = ArgParser();
  addPatrolOptions(parser);
  return parsePatrolOptions(parser.parse(arguments));
}

/// A transport that must never be used.
final class _NoNetwork implements LiveHttp {
  @override
  Future<LiveResponse> send(LiveRequest request) => throw StateError('network: ${request.url}');

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw StateError('network: ${request.url}');

  @override
  void close() {}
}

void main() {
  group('arguments', () {
    test('named platforms keep the table order', () {
      expect(_parse(['douyu', 'bilibili']).targets.map((target) => target.site), ['bilibili', 'douyu']);
    });

    test('--domestic, --overseas and --all select 18, 16 and 34 platforms', () {
      expect(_parse(['--domestic']).targets, hasLength(18));
      expect(_parse(['--overseas']).targets, hasLength(16));
      expect(_parse(['--all']).targets, hasLength(34));
      expect(_parse(['--domestic']).targets.every((target) => !target.overseas), isTrue);
    });

    test('options are read', () {
      final options = _parse([
        'huya',
        '--proxy',
        '127.0.0.1:7890',
        '--danmaku',
        '60',
        '--out',
        'a.md',
        '--json',
        'a.json',
      ]);
      expect(options.proxy, const HttpProxyRoute('127.0.0.1', 7890));
      expect(options.danmakuSeconds, 60);
      expect(options.out, 'a.md');
      expect(options.json, 'a.json');
    });

    test('bad arguments are refused', () {
      expect(() => _parse([]), throwsFormatException);
      expect(() => _parse(['nosuch']), throwsFormatException);
      expect(() => _parse(['huya', '--danmaku', '-1']), throwsFormatException);
      expect(() => _parse(['huya', '--proxy', 'localhost']), throwsFormatException);
      expect(() => _parse(['huya', '--proxy', 'localhost:99999']), throwsFormatException);
    });

    test('the command turns bad arguments into a usage error (exit 64)', () async {
      final runner = CommandRunner<int>('live_cli', 'test')..addCommand(PatrolCommand());
      await expectLater(runner.run(['patrol']), throwsA(isA<UsageException>()));
      await expectLater(runner.run(['patrol', 'nosuch']), throwsA(isA<UsageException>()));
    });
  });

  test('the table has the 34 platforms of SiteIds without IPTV, and a factory for each', () {
    expect(patrolTargets.map((target) => target.site), [
      for (final id in SiteIds.supported)
        if (id != SiteIds.iptv) id,
    ]);
    expect(siteFactories().keys.toSet(), patrolTargets.map((target) => target.site).toSet());
  });

  test('domestic platforms are direct and overseas ones use the proxy', () {
    final policy = patrolProxyPolicy(
      overseas: overseasTargets.map((target) => target.site),
      overseasProxy: const HttpProxyRoute('127.0.0.1', 7890),
    );
    final url = Uri.parse('https://example.com/');
    expect(policy.routeFor('bilibili', url), const DirectRoute());
    expect(policy.routeFor('twitch', url), const HttpProxyRoute('127.0.0.1', 7890));
  });

  group('runPatrol', () {
    test('without a proxy overseas platforms are not reached and nothing fails', () async {
      final report = await runPatrol(_parse(['twitch', 'youtube']), httpFor: (_) => _NoNetwork());
      for (final site in report.sites) {
        expect(site.results.map((result) => result.outcome).toSet(), {Outcome.notRun});
        expect(site.results.first.note, contains('没有代理'));
      }
      expect(report.hasFailure, isFalse);
      expect(report.proxied, isFalse);
    });

    test('a failure of a domestic platform makes the report fail (exit 1)', () async {
      final site = FakeSite()..recommend = {1: <LiveRoom>[]};
      final report = await runPatrol(
        _parse(['bilibili']),
        factories: {'bilibili': (_, _) => site},
        httpFor: (_) => _NoNetwork(),
      );
      expect(report.sites.single.network, '直连');
      expect(report.hasFailure, isTrue);
    });

    test('Kick is skipped as a whole and does not fail', () async {
      final report = await runPatrol(
        _parse(['kick', '--proxy', '127.0.0.1:7890']),
        factories: {'kick': (_, _) => FakeSite(id: 'kick')},
        httpFor: (_) => _NoNetwork(),
      );
      expect(report.sites.single.results.first.note, contains('Android'));
      expect(report.hasFailure, isFalse);
    });
  });
}
