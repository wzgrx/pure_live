import 'package:live_cli/src/patrol/targets.dart';
import 'package:meta/meta.dart';

/// The verdict of one check; the report has exactly these four words.
enum Outcome {
  /// Works.
  ok('正常'),

  /// Broken (or the platform answered in a way the check rejects).
  failed('失败'),

  /// Could not be checked this time (no proxy, no live room, stopped).
  notRun('没测到'),

  /// The platform does not offer it.
  unsupported('不支持');

  new(this.label);

  /// The Chinese word of the report.
  final String label;

  /// The outcome named [label], or null.
  static Outcome? byLabel(String label) {
    for (final outcome in values) {
      if (outcome.label == label || outcome.name == label) return outcome;
    }
    return null;
  }
}

/// The result of one check.
@immutable
final class CheckResult {
  /// Creates the result.
  const new(this.check, this.outcome, this.note, {this.elapsed = Duration.zero});

  /// Reads [toJson]'s output.
  factory fromJson(Map<String, Object?> json) => CheckResult(
    CheckId.byCode(json['check']! as String)!,
    Outcome.byLabel(json['outcome']! as String)!,
    json['note']! as String,
    elapsed: Duration(milliseconds: json['elapsedMs']! as int),
  );

  /// Which check.
  final CheckId check;

  /// The verdict.
  final Outcome outcome;

  /// What was seen; for a failure the error kind, status or code and step.
  final String note;

  /// How long the check took.
  final Duration elapsed;

  /// Machine-readable form.
  Map<String, Object?> toJson() => {
    'check': check.code,
    'title': check.title,
    'outcome': outcome.name,
    'note': note,
    'elapsedMs': elapsed.inMilliseconds,
  };
}

/// One platform's results.
@immutable
final class SiteRun {
  /// Creates the run.
  new({
    required this.site,
    required this.name,
    required this.network,
    required List<CheckResult> results,
    required this.elapsed,
  }) : results = List.unmodifiable(results);

  /// Reads [toJson]'s output.
  factory fromJson(Map<String, Object?> json) => SiteRun(
    site: json['site']! as String,
    name: json['name']! as String,
    network: json['network']! as String,
    results: [
      for (final item in json['results']! as List<Object?>) CheckResult.fromJson(item! as Map<String, Object?>),
    ],
    elapsed: Duration(milliseconds: json['elapsedMs']! as int),
  );

  /// Platform id.
  final String site;

  /// Display name.
  final String name;

  /// `直连` or `代理`.
  final String network;

  /// The checks, in order.
  final List<CheckResult> results;

  /// Network time of the platform.
  final Duration elapsed;

  /// How many checks ended with [outcome].
  int count(Outcome outcome) => results.where((result) => result.outcome == outcome).length;

  /// Whether any check failed.
  bool get hasFailure => count(Outcome.failed) > 0;

  /// Machine-readable form.
  Map<String, Object?> toJson() => {
    'site': site,
    'name': name,
    'network': network,
    'elapsedMs': elapsed.inMilliseconds,
    'counts': {for (final outcome in Outcome.values) outcome.name: count(outcome)},
    'results': [for (final result in results) result.toJson()],
  };
}

/// A whole patrol.
@immutable
final class PatrolReport {
  /// Creates the report.
  new({
    required this.startedAt,
    required this.finishedAt,
    required this.proxied,
    required List<SiteRun> sites,
    this.danmakuSeconds = 0,
  }) : sites = List.unmodifiable(sites);

  /// Reads [toJson]'s output.
  factory fromJson(Map<String, Object?> json) => PatrolReport(
    startedAt: DateTime.parse(json['startedAt']! as String),
    finishedAt: DateTime.parse(json['finishedAt']! as String),
    proxied: json['proxied']! as bool,
    danmakuSeconds: json['danmakuSeconds']! as int,
    sites: [for (final item in json['sites']! as List<Object?>) SiteRun.fromJson(item! as Map<String, Object?>)],
  );

  /// Start (UTC).
  final DateTime startedAt;

  /// End (UTC).
  final DateTime finishedAt;

  /// Whether overseas platforms went through a proxy.
  final bool proxied;

  /// `--danmaku` seconds (0 = P13 not run).
  final int danmakuSeconds;

  /// Platforms, in order.
  final List<SiteRun> sites;

  /// Whether any check failed (exit code 1).
  bool get hasFailure => sites.any((site) => site.hasFailure);

  /// Machine-readable form.
  Map<String, Object?> toJson() => {
    'startedAt': startedAt.toUtc().toIso8601String(),
    'finishedAt': finishedAt.toUtc().toIso8601String(),
    'proxied': proxied,
    'anonymous': true,
    'danmakuSeconds': danmakuSeconds,
    'sites': [for (final site in sites) site.toJson()],
  };
}
