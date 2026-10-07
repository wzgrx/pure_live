import 'dart:convert';
import 'dart:io';

import 'package:live_cli/src/patrol/result.dart';

/// [url] as the report may show it: host and the first two path segments,
/// without query, fragment or user info (signed parameters, tokens).
String redact(Uri url) {
  final segments = url.pathSegments.where((segment) => segment.isNotEmpty).toList();
  final kept = segments.take(2).join('/');
  final more = segments.length > 2 ? '/…' : '';
  return '${url.host}${kept.isEmpty ? '' : '/$kept'}$more';
}

final RegExp _url = RegExp(r'''[a-z][a-z0-9+.-]*://[^\s"'<>|)\]]+''', caseSensitive: false);
final RegExp _ipv4 = RegExp(r'(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])');

// The ranges tools/gate/check_fixtures.py lets through: unspecified,
// private, loopback, link-local, CGNAT and the documentation ranges.
const List<(int, int)> _allowedNetworks = [
  (0x00000000, 8),
  (0x0A000000, 8),
  (0x64400000, 10),
  (0x7F000000, 8),
  (0xA9FE0000, 16),
  (0xAC100000, 12),
  (0xC0A80000, 16),
  (0xC0000200, 24),
  (0xC6336400, 24),
  (0xCB007100, 24),
];

bool _allowedAddress(String text) {
  final parts = text.split('.').map(int.parse).toList();
  if (parts.any((part) => part > 255)) return true; // a version number, not an address
  final value = (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
  for (final (network, bits) in _allowedNetworks) {
    final mask = (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF;
    if (value & mask == network) return true;
  }
  return false;
}

/// [text] fit for the repository: every URL [redact]ed and every IPv4
/// address outside the reserved and documentation ranges (the rule of
/// `tools/gate/check_fixtures.py`) replaced with `x.x.x.x`.
String scrub(String text) {
  final withoutUrls = text.replaceAllMapped(_url, (match) {
    final uri = Uri.tryParse(match.group(0)!);
    return uri == null || uri.host.isEmpty ? '<地址>' : redact(uri);
  });
  return withoutUrls.replaceAllMapped(_ipv4, (match) => _allowedAddress(match.group(0)!) ? match.group(0)! : 'x.x.x.x');
}

String _cell(String text) => scrub(text).replaceAll(RegExp(r'[\r\n]+'), ' ').replaceAll('|', r'\|').trim();

/// `52 秒`, `3 分 07 秒`.
String formatDuration(Duration duration) {
  final seconds = (duration.inMilliseconds / 1000).round();
  if (seconds < 60) return '$seconds 秒';
  return '${seconds ~/ 60} 分 ${(seconds % 60).toString().padLeft(2, '0')} 秒';
}

String _utc(DateTime time) {
  final utc = time.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)} ${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}';
}

/// The Markdown report: a header line (time UTC, network, anonymous, time
/// per platform and in total), then one `| 检查项 | 结果 | 说明 |` table per
/// platform, the format of the platforms' record.md "真实环境检查" tables.
/// Every note goes through [scrub].
String markdownReport(PatrolReport report) {
  final buffer = StringBuffer()
    ..writeln('# 平台巡检 ${_utc(report.startedAt).substring(0, 10)}')
    ..writeln()
    ..writeln(
      [
        '${_utc(report.startedAt)}～${_utc(report.finishedAt).substring(11)} UTC',
        '国内直连，海外${report.proxied ? '经代理' : '没有代理'}',
        '匿名（不登录、不发言）',
        '弹幕${report.danmakuSeconds > 0 ? ' ${report.danmakuSeconds} 秒' : '不跑'}',
        '总用时 ${formatDuration(report.finishedAt.difference(report.startedAt))}。',
      ].join('；'),
    )
    ..writeln()
    ..writeln('| 平台 | 网络 | 用时 | 正常 | 失败 | 没测到 | 不支持 |')
    ..writeln('|---|---|---|---|---|---|---|');
  for (final site in report.sites) {
    buffer.writeln(
      '| ${site.name} | ${site.network} | ${formatDuration(site.elapsed)} | ${site.count(Outcome.ok)} | '
      '${site.count(Outcome.failed)} | ${site.count(Outcome.notRun)} | ${site.count(Outcome.unsupported)} |',
    );
  }
  for (final site in report.sites) {
    buffer
      ..writeln()
      ..writeln('## ${site.name}（${site.site}）')
      ..writeln()
      ..writeln('${site.network}，用时 ${formatDuration(site.elapsed)}。')
      ..writeln()
      ..writeln('| 检查项 | 结果 | 说明 |')
      ..writeln('|---|---|---|');
    for (final result in site.results) {
      buffer.writeln('| ${result.check.label} | ${result.outcome.label} | ${_cell(result.note)} |');
    }
  }
  return buffer.toString();
}

/// The JSON report, notes scrubbed like [markdownReport].
String jsonReport(PatrolReport report) {
  final scrubbed = PatrolReport(
    startedAt: report.startedAt,
    finishedAt: report.finishedAt,
    proxied: report.proxied,
    danmakuSeconds: report.danmakuSeconds,
    sites: [
      for (final site in report.sites)
        SiteRun(
          site: site.site,
          name: site.name,
          network: site.network,
          elapsed: site.elapsed,
          results: [
            for (final result in site.results)
              CheckResult(result.check, result.outcome, scrub(result.note), elapsed: result.elapsed),
          ],
        ),
    ],
  );
  return const JsonEncoder.withIndent('  ').convert(scrubbed.toJson());
}

/// Writes [text] to [path], creating its directory.
Future<void> writeReport(String path, String text) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(text);
}
