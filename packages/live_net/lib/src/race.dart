import 'dart:async';

import 'package:live_net/src/live_http.dart';
import 'package:live_net/src/request.dart';
import 'package:meta/meta.dart';

/// Runs [task] for every one of [urls] at once and returns the first non-null
/// result; the others are cancelled through their [CancelToken]. Returns null
/// when every task failed or gave null, or when [timeout] elapsed.
///
/// 3.x's `RaceHttp` waited for the whole timeout even after every mirror had
/// failed (30 seconds for the update check) and let the losing requests run
/// on; both are fixed here.
Future<T?> raceFirst<T extends Object>(
  Iterable<Uri> urls,
  Future<T?> Function(Uri url, CancelToken cancel) task, {
  required Duration timeout,
}) async {
  final list = urls.toList();
  if (list.isEmpty) return null;
  final winner = Completer<T?>();
  final tokens = [for (final _ in list) CancelToken()];
  var pending = list.length;
  for (var index = 0; index < list.length; index++) {
    unawaited(
      Future(() => task(list[index], tokens[index]))
          .then<void>(
            (result) {
              if (result != null && !winner.isCompleted) winner.complete(result);
            },
            onError: (Object _) {
              // Another URL may still win.
            },
          )
          .whenComplete(() {
            pending--;
            if (pending == 0 && !winner.isCompleted) winner.complete(null);
          }),
    );
  }
  final timer = Timer(timeout, () {
    if (!winner.isCompleted) winner.complete(null);
  });
  final result = await winner.future;
  timer.cancel();
  for (final token in tokens) {
    token.cancel();
  }
  return result;
}

/// The first JSON object any of [urls] answers with status 200 (update
/// manifests and Huya's endpoints are fetched from several mirrors).
Future<Map<String, Object?>?> raceJson(
  LiveHttp http,
  String site,
  Iterable<Uri> urls, {
  Map<String, String> headers = const {},
  Duration timeout = const Duration(seconds: 30),
}) => raceFirst<Map<String, Object?>>(urls, (url, cancel) async {
  final response = await http.send(
    LiveRequest(site: site, url: url, headers: headers, timeout: timeout, cancel: cancel),
  );
  if (response.status != 200) return null;
  final json = response.json;
  return json is Map<String, Object?> ? json : null;
}, timeout: timeout);

/// The first of [urls] that answers a one-byte ranged GET with 200 or 206,
/// or null. Several GitHub mirrors reject HEAD; a one-byte GET takes the
/// same route without downloading the file.
Future<Uri?> fastestUrl(
  LiveHttp http,
  String site,
  Iterable<Uri> urls, {
  Map<String, String> headers = const {},
  Duration timeout = const Duration(seconds: 60),
}) => raceFirst<Uri>(urls, (url, cancel) async {
  final response = await http.open(
    LiveRequest(site: site, url: url, headers: {'range': 'bytes=0-0', ...headers}, timeout: timeout, cancel: cancel),
  );
  await response.discard();
  return response.status == 200 || response.status == 206 ? url : null;
}, timeout: timeout);

/// The download mirrors of one file in a GitHub repository, in the order
/// they are listed (3.x's `GitHubMirror`): the raw URL, the ghproxy-style
/// prefixes in front of it, kkgithub, then jsDelivr and its Fastly node.
/// The update check, font downloads and Huya's player configuration race
/// them with [raceJson] or [fastestUrl].
@immutable
final class GitHubMirror {
  /// Mirrors of [owner]/[repo] at [branch].
  const new({required this.owner, required this.repo, this.branch = 'master'});

  /// Repository owner.
  final String owner;

  /// Repository name.
  final String repo;

  /// Branch the files are read from.
  final String branch;

  /// Prefixes put in front of the raw URL, steadiest first (3.x's order:
  /// the first six serve ranged requests, the last four only raw files).
  static const List<String> rawPrefixes = [
    'https://cdn.gh-proxy.org/',
    'https://edgeone.gh-proxy.org/',
    'https://hk.gh-proxy.org/',
    'https://gh.noki.eu.org/',
    'https://gh-proxy.com/',
    'https://slink.ltd/',
    'https://ghproxy.link/',
    'https://gh-proxy.net/',
    'https://gitproxy.click/',
    'https://v6.gh-proxy.org/',
    'https://ghproxy.net/',
    'https://wget.la/',
    'https://gh.catmak.name/',
    'https://g.blfrp.cn/',
  ];

  /// The `raw.githubusercontent.com` URL of [path].
  Uri raw(String path) => Uri.parse('https://raw.githubusercontent.com/$owner/$repo/$branch/$path');

  /// Every mirror of [path], without duplicates.
  List<Uri> mirrors(String path) {
    final raw = this.raw(path).toString();
    return List.unmodifiable(
      {
        raw,
        for (final prefix in rawPrefixes) '$prefix$raw',
        'https://raw.kkgithub.com/$owner/$repo/$branch/$path',
        'https://cdn.jsdelivr.net/gh/$owner/$repo@$branch/$path',
        'https://fastly.jsdelivr.net/gh/$owner/$repo@$branch/$path',
      }.map(Uri.parse),
    );
  }
}
