import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/iptv/iptv_repository.dart';
import 'package:pure_live_app/features/iptv/xtream.dart';

/// Runs a parse off the UI isolate; tests run it inline.
typedef IptvCompute = Future<R> Function<R>(R Function() task);

Future<R> _isolate<R>(R Function() task) => Isolate.run(task);

/// What an import or sync stored.
final class IptvSyncResult {
  const new({required this.id, required this.items, required this.channels, required this.issues});

  /// Playlist or guide source id.
  final int id;

  /// Entries (playlists) or programmes (guides) stored.
  final int items;

  /// Distinct channels.
  final int channels;

  /// Skipped lines or items.
  final int issues;
}

/// A file or download that holds nothing usable.
final class IptvEmptyError implements Exception {
  const new({required this.guide, this.detail});

  /// Whether it was a programme guide (else a playlist).
  final bool guide;

  /// First parser issue, for logs.
  final String? detail;

  @override
  String toString() => 'IptvEmptyError(${guide ? 'guide' : 'playlist'}: $detail)';
}

/// A source that is not an http(s) URL.
final class IptvBadUrlError implements Exception {
  const new();
}

/// What to tell the user about a failed import or sync (principles rule 3).
String iptvErrorText(Object error) => switch (error) {
  IptvEmptyError(guide: true) => '没有识别出节目单，确认是 XMLTV 或 JSON 格式',
  IptvEmptyError() => '没有识别出频道，确认是 M3U、TXT 或 JSON 播放列表',
  IptvBadUrlError() => '请输入 http 或 https 开头的网址',
  XtreamRejectedError(:final message) => message,
  XtreamMissingError() => '找不到这个 Xtream 账号的登录信息，删除后重新登录',
  NotFound() => '地址不存在（404），检查网址是否还有效',
  NetworkFailure() || TransportFailure() => '网络连接失败，检查网络或代理后重试',
  FileSystemException() => '读不到文件，重新导入一次',
  FormatException() => '文件格式不对',
  _ => '同步失败',
};

/// Imports and syncs playlists and programme guides (spec/modules/iptv.md
/// §6): download or read, parse off the UI isolate, then replace the stored
/// data in one transaction. A failure keeps the old data and records why.
final class IptvSync {
  new({
    required this.store,
    required this.fetcher,
    required this.settings,
    required this.directory,
    this.onChanged,
    this.xtream,
    DateTime Function()? now,
    IptvCompute? compute,
  }) : _now = now ?? DateTime.now,
       _compute = compute ?? _isolate;

  final IptvStore store;
  final IptvFetcher fetcher;
  final SettingsStore settings;

  /// `<data root>/IPTV`, where imported files are kept.
  final Future<Directory> Function() directory;

  /// Called after stored channels or programmes changed.
  final void Function()? onChanged;

  /// Xtream accounts (F-IPTV-07); null where the secret store is missing.
  final XtreamVault? xtream;

  /// The address to download [source] from: itself, or an Xtream account's
  /// playlist or guide.
  Uri _remote(String source) {
    final id = xtreamIdOf(source);
    if (id == null) return Uri.parse(source);
    final account = xtream?.read(id);
    if (account == null) throw const XtreamMissingError();
    return source.endsWith('#guide') ? account.guideUri : account.playlistUri;
  }

  final DateTime Function() _now;
  final IptvCompute _compute;
  final Map<String, Future<IptvSyncResult>> _running = {};
  final _random = Random();

  String? get _globalAgent {
    final agent = settings.get(Settings.iptvUserAgent).trim();
    return agent.isEmpty ? null : agent;
  }

  /// One run per key at a time; a second caller gets the running one.
  Future<IptvSyncResult> _once(String key, Future<IptvSyncResult> Function() run) =>
      // The block body matters: returning the removed future from the
      // callback would make the run wait for itself.
      _running[key] ??= run().whenComplete(() {
        unawaited(_running.remove(key));
      });

  // -------------------------------------------------------------- playlists

  /// Adds the playlist at [url] (named [name], else after the URL) after a
  /// successful download and parse. A URL already added is synced instead.
  Future<IptvSyncResult> importUrl(String url, {String? name}) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) {
      throw const IptvBadUrlError();
    }
    final existing = (await store.playlists()).where((playlist) => playlist.source == uri.toString()).firstOrNull;
    if (existing != null) return await syncPlaylist(existing);
    final parsed = await _parsePlaylist(await fetcher.download(uri, userAgent: _globalAgent));
    final id = await store.addPlaylist(name: _name(name, uri.pathSegments.lastOrNull ?? uri.host), source: '$uri');
    return await _storePlaylist(id, parsed);
  }

  /// Adds a playlist file: the bytes are parsed, then kept under
  /// `IPTV/playlists/` so a later sync can read them again.
  Future<IptvSyncResult> importFile({required String fileName, required List<int> bytes, String? name}) async {
    final parsed = await _parsePlaylist(bytes);
    final file = await _keep('playlists', fileName, bytes);
    final id = await store.addPlaylist(name: _name(name, fileName), source: file.path);
    return await _storePlaylist(id, parsed);
  }

  /// Downloads (URL) or re-reads (kept file) [playlist] and replaces its
  /// entries; a failure is recorded and rethrown.
  Future<IptvSyncResult> syncPlaylist(IptvPlaylistRecord playlist) => _once('playlist:${playlist.id}', () async {
    try {
      final bytes = playlist.isRemote
          ? await fetcher.download(_remote(playlist.source), userAgent: playlist.userAgent ?? _globalAgent)
          : await File(playlist.source).readAsBytes();
      return await _storePlaylist(playlist.id, await _parsePlaylist(bytes));
    } on Object catch (error) {
      await store.recordPlaylistFailure(playlist.id, iptvErrorText(error), at: _now());
      rethrow;
    }
  });

  /// Deletes [playlist] and the file kept for it; an Xtream playlist also
  /// takes its guide and its stored account.
  Future<void> deletePlaylist(IptvPlaylistRecord playlist) async {
    await store.deletePlaylist(playlist.id);
    if (!playlist.isRemote) await _discard(playlist.source);
    if (xtreamIdOf(playlist.source) case final id?) {
      for (final guide in await store.guideSources()) {
        if (guide.source == '$xtreamScheme$id#guide') await store.deleteGuideSource(guide.id);
      }
      await xtream?.delete(id);
    }
    onChanged?.call();
  }

  /// F-IPTV-07: checks [account] with the provider, keeps it in the secret
  /// store and adds its line-up and guide. Throws [XtreamRejectedError] when
  /// the provider refuses the account.
  Future<IptvSyncResult> importXtream(XtreamAccount account, {String? name}) async {
    final vault = xtream;
    if (vault == null) throw const XtreamMissingError();
    final Object? answer;
    try {
      answer = jsonDecode(utf8.decode(await fetcher.download(account.authUri, userAgent: _globalAgent)));
    } on FormatException {
      throw const XtreamRejectedError('服务器的回应不是 Xtream 接口，检查服务器地址');
    }
    final status = parseXtreamStatus(answer);
    if (!status.usable) throw XtreamRejectedError(status.problem);
    final parsed = await _parsePlaylist(await fetcher.download(account.playlistUri, userAgent: _globalAgent));
    final key =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_random.nextInt(1 << 20).toRadixString(36)}';
    await vault.save(key, account);
    // The host as is: _name would take `.com` for a file extension.
    final title = name == null || name.trim().isEmpty ? account.defaultName : name.trim();
    final id = await store.addPlaylist(name: title, source: '$xtreamScheme$key');
    // The provider's own guide, never the credentialed url-tvg of the file.
    final result = await _storePlaylist(id, parsed, adoptGuide: false);
    final guideId = await store.addGuideSource(name: '$title 节目单', source: '$xtreamScheme$key#guide');
    try {
      await syncGuide((await store.guideSources()).firstWhere((source) => source.id == guideId));
    } on Object {
      // The guide keeps its error; the guide page offers a retry.
    }
    return result;
  }

  Future<ParsedPlaylist> _parsePlaylist(List<int> bytes) async {
    final parsed = await _compute(() => parsePlaylistBytes(bytes));
    if (parsed.entries.isEmpty) throw IptvEmptyError(guide: false, detail: parsed.issues.firstOrNull?.toString());
    return parsed;
  }

  Future<IptvSyncResult> _storePlaylist(int id, ParsedPlaylist parsed, {bool adoptGuide = true}) async {
    final xtreamPlaylist = !adoptGuide || isXtreamSource((await store.playlist(id))?.source ?? '');
    await store.replaceEntries(
      id,
      [for (final entry in parsed.entries) StoreIptvRepository.recordOf(entry)],
      syncedAt: _now(),
      // An Xtream file names its guide with the password in the URL.
      guideUrl: xtreamPlaylist ? null : parsed.guideUrls.firstOrNull?.toString(),
    );
    onChanged?.call();
    if (!xtreamPlaylist) await _adoptGuide(parsed.guideUrls);
    return IptvSyncResult(
      id: id,
      items: parsed.entries.length,
      channels: {for (final entry in parsed.entries) entry.name}.length,
      issues: parsed.issues.length,
    );
  }

  /// §6: the playlist's guide becomes the first guide source when there is
  /// none yet (best effort; the guide page offers it otherwise).
  Future<void> _adoptGuide(List<Uri> urls) async {
    if (urls.isEmpty || (await store.guideSources()).isNotEmpty) return;
    try {
      await addGuideUrl(urls.first.toString());
    } on Object {
      // The source stays with its error; the guide page shows it.
    }
  }

  // ------------------------------------------------------------------ guides

  /// Adds the guide at [url] and syncs it; the source is kept (with its error)
  /// when the first sync fails, so the user can retry. A URL already added is
  /// synced instead.
  Future<IptvSyncResult> addGuideUrl(String url, {String? name}) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) {
      throw const IptvBadUrlError();
    }
    final existing = (await store.guideSources()).where((source) => source.source == uri.toString()).firstOrNull;
    if (existing != null) return await syncGuide(existing);
    final id = await store.addGuideSource(name: _name(name, uri.pathSegments.lastOrNull ?? uri.host), source: '$uri');
    final added = (await store.guideSources()).firstWhere((source) => source.id == id);
    return await syncGuide(added);
  }

  /// Adds a guide file (kept under `IPTV/guides/`).
  Future<IptvSyncResult> addGuideFile({required String fileName, required List<int> bytes, String? name}) async {
    final parsed = await _parseGuide(bytes);
    final file = await _keep('guides', fileName, bytes);
    final id = await store.addGuideSource(name: _name(name, fileName), source: file.path);
    return await _storeGuide(id, parsed);
  }

  /// Downloads or re-reads [source] and replaces its channels and programmes.
  Future<IptvSyncResult> syncGuide(IptvGuideSourceRecord source) => _once('guide:${source.id}', () async {
    try {
      final bytes = source.isRemote
          ? await fetcher.download(_remote(source.source), userAgent: _globalAgent)
          : await File(source.source).readAsBytes();
      return await _storeGuide(source.id, await _parseGuide(bytes));
    } on Object catch (error) {
      await store.recordGuideFailure(source.id, iptvErrorText(error), at: _now());
      rethrow;
    }
  });

  /// Deletes [source] and the file kept for it.
  Future<void> deleteGuide(IptvGuideSourceRecord source) async {
    await store.deleteGuideSource(source.id);
    if (!source.isRemote) await _discard(source.source);
    onChanged?.call();
  }

  /// Selects [source] (null: none).
  Future<void> selectGuide(IptvGuideSourceRecord? source) async {
    await store.selectGuideSource(source?.id);
    onChanged?.call();
  }

  Future<ParsedGuide> _parseGuide(List<int> bytes) async {
    final now = _now();
    final parsed = await _compute(() => parseGuideBytes(bytes, now: now));
    if (parsed.channels.isEmpty && parsed.programmes.isEmpty) {
      throw IptvEmptyError(guide: true, detail: parsed.issues.firstOrNull?.toString());
    }
    return parsed;
  }

  Future<IptvSyncResult> _storeGuide(int id, ParsedGuide parsed) async {
    await store.replaceGuide(
      id,
      [
        for (final channel in parsed.channels)
          IptvGuideChannelRecord(channelId: channel.id, names: channel.names, icon: channel.icon),
      ],
      [
        for (final programme in parsed.programmes)
          IptvProgrammeRecord(
            channelId: programme.channelId,
            start: programme.start,
            stop: programme.stop,
            title: programme.title,
            subtitle: programme.subtitle,
            description: programme.description,
            catchupId: programme.catchupId,
          ),
      ],
      syncedAt: _now(),
    );
    onChanged?.call();
    return IptvSyncResult(
      id: id,
      items: parsed.programmes.length,
      channels: parsed.channels.length,
      issues: parsed.issues.length,
    );
  }

  // -------------------------------------------------------------- automatic

  /// Whether a URL source with auto sync on is due: never tried, or tried
  /// longer ago than the interval (F-IPTV-03).
  bool _due({required bool remote, required bool autoSync, required DateTime? lastAttemptAt}) {
    if (!remote || !autoSync) return false;
    if (lastAttemptAt == null) return true;
    final interval = Duration(hours: settings.get(Settings.iptvAutoSyncHours));
    return !_now().isBefore(lastAttemptAt.add(interval));
  }

  /// Syncs the due URL playlists and guide sources one after another, then
  /// drops programmes older than the guide window; returns how many failed.
  Future<int> syncDue() async {
    var failed = 0;
    for (final playlist in await store.playlists()) {
      if (!_due(remote: playlist.isRemote, autoSync: playlist.autoSync, lastAttemptAt: playlist.lastAttemptAt)) {
        continue;
      }
      try {
        await syncPlaylist(playlist);
      } on Object {
        failed++;
      }
    }
    for (final source in await store.guideSources()) {
      if (!_due(remote: source.isRemote, autoSync: source.autoSync, lastAttemptAt: source.lastAttemptAt)) continue;
      try {
        await syncGuide(source);
      } on Object {
        failed++;
      }
    }
    await store.pruneProgrammes(_now().subtract(guideKeepBack));
    return failed;
  }

  /// Syncs every playlist and guide source now; returns how many failed.
  Future<int> syncAll() async {
    var failed = 0;
    for (final playlist in await store.playlists()) {
      try {
        await syncPlaylist(playlist);
      } on Object {
        failed++;
      }
    }
    for (final source in await store.guideSources()) {
      try {
        await syncGuide(source);
      } on Object {
        failed++;
      }
    }
    return failed;
  }

  // ------------------------------------------------------------------- files

  static String _name(String? given, String fallback) {
    final name = given?.trim();
    if (name != null && name.isNotEmpty) return name;
    // URL path segments arrive decoded; file names are used as they are.
    var base = fallback.split(RegExp(r'[/\\]')).last;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    return base.isEmpty ? '播放列表' : base;
  }

  Future<File> _keep(String folder, String fileName, List<int> bytes) async {
    final root = await directory();
    final dir = Directory('${root.path}${Platform.pathSeparator}$folder');
    await dir.create(recursive: true);
    final dot = fileName.lastIndexOf('.');
    final extension = dot > 0 && fileName.length - dot <= 6 ? fileName.substring(dot).toLowerCase() : '.txt';
    final stamp = _now().millisecondsSinceEpoch;
    final file = File('${dir.path}${Platform.pathSeparator}${stamp}_${_random.nextInt(1 << 32)}$extension');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Deletes a kept file, only inside the IPTV folder.
  Future<void> _discard(String path) async {
    final root = await directory();
    if (!path.startsWith(root.path)) return;
    try {
      await File(path).delete();
    } on FileSystemException {
      // Already gone.
    }
  }
}

/// The Xtream account of a source is not in the secret store (restored on
/// another device without secrets, or the store is unavailable).
final class XtreamMissingError implements Exception {
  const new();

  @override
  String toString() => '找不到这个 Xtream 账号的登录信息，删除后重新登录';
}

/// The provider refused the account.
final class XtreamRejectedError implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => message;
}
