import 'dart:convert';

import 'package:live_cli/live_cli.dart';
import 'package:test/test.dart';

PatrolReport _report() => PatrolReport(
  startedAt: DateTime.utc(2026, 10, 8, 1, 2, 3),
  finishedAt: DateTime.utc(2026, 10, 8, 1, 5, 10),
  proxied: false,
  sites: [
    SiteRun(
      site: 'bilibili',
      name: '哔哩哔哩',
      network: '直连',
      elapsed: const Duration(seconds: 52),
      results: const [
        CheckResult(CheckId.p1, Outcome.ok, '第 1 页 30 个', elapsed: Duration(seconds: 1)),
        CheckResult(
          CheckId.p10,
          Outcome.failed,
          'a|b 读 https://cn-gotcha.example/live-bvc/123/live_1.flv?expires=1&sign=secret 来自 8.8.8.8',
        ),
      ],
    ),
  ],
);

void main() {
  test('redact keeps the host and two path segments, no query', () {
    expect(
      redact(Uri.parse('https://cdn.example/live-bvc/123/live_1.flv?sign=secret#x')),
      'cdn.example/live-bvc/123/…',
    );
    expect(redact(Uri.parse('https://cdn.example/a/b')), 'cdn.example/a/b');
    expect(redact(Uri.parse('https://cdn.example/?token=1')), 'cdn.example');
  });

  test('scrub keeps documentation and private addresses and replaces public ones', () {
    expect(scrub('203.0.113.7 和 192.168.1.2'), '203.0.113.7 和 192.168.1.2');
    expect(scrub('出口 8.8.8.8'), '出口 x.x.x.x');
    expect(scrub('版本 1.2.3.400'), '版本 1.2.3.400');
    expect(scrub('见 http://8.8.8.8:8080/a/b/c?d=1'), '见 x.x.x.x/a/b/…');
  });

  test('the Markdown report has the record.md table and scrubbed notes', () {
    final markdown = markdownReport(_report());
    expect(markdown, contains('2026-10-08 01:02:03～01:05:10 UTC；国内直连，海外没有代理；匿名'));
    expect(markdown, contains('总用时 3 分 07 秒'));
    expect(markdown, contains('| 哔哩哔哩 | 直连 | 52 秒 | 1 | 1 | 0 | 0 |'));
    expect(markdown, contains('| 检查项 | 结果 | 说明 |\n|---|---|---|\n| P1 推荐 | 正常 | 第 1 页 30 个 |'));
    expect(markdown, contains(r'| P10 线路 | 失败 | a\|b 读 cn-gotcha.example/live-bvc/123/… 来自 x.x.x.x |'));
    expect(markdown, isNot(contains('secret')));
    expect(markdown, isNot(contains('8.8.8.8')));
  });

  test('the JSON report round-trips and is scrubbed', () {
    final text = jsonReport(_report());
    expect(text, isNot(contains('secret')));
    final back = PatrolReport.fromJson(jsonDecode(text) as Map<String, Object?>);
    expect(back.startedAt, DateTime.utc(2026, 10, 8, 1, 2, 3));
    expect(back.sites.single.results.map((result) => result.outcome), [Outcome.ok, Outcome.failed]);
    expect(back.sites.single.results.first.elapsed, const Duration(seconds: 1));
    expect(back.hasFailure, isTrue);
  });

  test('durations read as seconds or minutes and seconds', () {
    expect(formatDuration(const Duration(milliseconds: 52400)), '52 秒');
    expect(formatDuration(const Duration(seconds: 187)), '3 分 07 秒');
  });
}
