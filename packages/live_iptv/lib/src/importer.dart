import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_iptv/src/guide/guide_parser.dart';
import 'package:live_iptv/src/guide/matcher.dart';
import 'package:live_iptv/src/library.dart';
import 'package:live_iptv/src/model.dart';
import 'package:live_iptv/src/playlist/playlist_parse_result.dart';
import 'package:live_iptv/src/playlist/playlist_parser.dart';
import 'package:live_iptv/src/reconcile.dart';
import 'package:live_iptv/src/text.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// How an import or sync ended.
enum IptvImportStatus {
  /// Saved.
  imported,

  /// The user declined to replace the playlist or guide of the same name.
  cancelled,

  /// Not a playlist or guide this app reads, or nothing in it.
  unsupportedFormat,

  /// Unreadable text or markup, a cut-off file, or an ambiguous sync; the
  /// saved data is kept.
  invalid,

  /// The download failed.
  networkFailed,

  /// The saved playlist or guide changed meanwhile; nothing was written.
  stale,

  /// Anything else (storage failure, ambiguous name).
  failed,
}

/// What an import or sync did.
@immutable
final class IptvImportResult {
  /// Creates a result.
  new(this.status, {this.id, List<PlaylistIssue> issues = const [], this.error}) : issues = List.unmodifiable(issues);

  /// How it ended.
  final IptvImportStatus status;

  /// Id of the saved playlist or guide source.
  final String? id;

  /// Lines of the playlist that were skipped.
  final List<PlaylistIssue> issues;

  /// The error behind a failure, for logs.
  final Object? error;

  /// Whether it was saved.
  bool get isImported => status == IptvImportStatus.imported;

  @override
  String toString() => 'IptvImportResult(${status.name}${error == null ? '' : ', $error'})';
}

/// Asks the user whether to replace the saved playlist or guide [name]
/// (3.x's "name exists" dialog); false keeps it.
typedef IptvReplaceConfirm = FutureOr<bool> Function(String name);

/// Imports, syncs and deletes playlists and programme guides (3.x's
/// `IptvImportManager`, `IptvSyncEngine`, `EpgImportManager`,
/// `EpgSyncEngine` and `AutoSyncScheduler`), over an [IptvLibrary].
///
/// - Imports run one at a time.
/// - A playlist with the same name (case-insensitive) is replaced after
///   [IptvReplaceConfirm] (or at once with `force`); its channels keep their
///   ids through [reconcileChannels].
/// - Local playlists are copied into [playlistDirectory]
///   (`playlist_<uuid>.<ext>`), so a sync re-reads the copy; the previous
///   copy is deleted after a successful replacement when nothing else uses
///   it.
/// - Network requests use platform key [site] (proxy rules) and time out
///   after [downloadTimeout].
final class IptvImporter {
  /// Creates an importer.
  new({
    required this.library,
    required this.http,
    required this.playlistDirectory,
    required this.selectedGuideSourceId,
    this.autoSyncEnabled = _off,
    this.legacyDecoder,
    this.now = DateTime.now,
    this.newId = randomUuid,
  });

  /// Platform key of IPTV downloads.
  static const String site = 'iptv';

  /// Download timeout.
  static const Duration downloadTimeout = Duration(minutes: 2);

  /// The built-in hot playlist (3.x `AutoSyncScheduler`).
  static const String hotPlaylistUrl = 'https://iptv-org.github.io/iptv/countries/cn.m3u';

  /// The default programme guide (3.x `AutoSyncScheduler`).
  static const String defaultGuideUrl = 'https://epg.zsdc.eu.org/t.xml.gz';

  /// Name of the built-in playlist and guide (3.x `iptvHotFile` without its
  /// extension).
  static const String hotName = 'hot';

  /// User-Agent of guide downloads (3.x's desktop Chrome string).
  static const String guideUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';

  /// Guide programmes older than this are pruned after a guide import.
  static const Duration programmeRetention = Duration(days: 2);

  /// Automatic sync interval bounds in hours (3.x settings).
  static const int minAutoSyncHours = 2;

  /// Upper bound of the interval.
  static const int maxAutoSyncHours = 72;

  /// Default interval.
  static const int defaultAutoSyncHours = 24;

  static bool _off() => false;

  /// Storage.
  final IptvLibrary library;

  /// Transport for downloads.
  final LiveHttp http;

  /// Where copies of local playlists are kept.
  final Directory playlistDirectory;

  /// The selected guide source id (3.x setting `selectedSourceId`); empty
  /// when none. Mappings are rebuilt against it after a playlist import.
  final String Function() selectedGuideSourceId;

  /// Whether new network playlists sync automatically (3.x setting
  /// `isAutoSyncEnabled`).
  final bool Function() autoSyncEnabled;

  /// Decoder for playlists that are not UTF-8 (GBK in the app).
  final IptvLegacyDecoder? legacyDecoder;

  /// Clock.
  final DateTime Function() now;

  /// New ids.
  final String Function() newId;

  Future<void> _tail = Future.value();
  Future<void>? _hotLoad;
  Future<EpgSource?>? _guideLoad;

  Future<T> _serial<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  // Playlists ---------------------------------------------------------------

  /// Imports playlist [bytes] in [format] as [name]. [url] is the network
  /// source; without it a copy is kept for syncs. [expected] makes this a
  /// sync of that saved playlist.
  Future<IptvImportResult> importPlaylist({
    required List<int> bytes,
    required IptvPlaylistFormat format,
    required String name,
    String url = '',
    bool isHot = false,
    bool force = false,
    IptvPlaylist? expected,
    IptvReplaceConfirm? confirmReplace,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return IptvImportResult(IptvImportStatus.invalid, error: 'Empty playlist name');
    final String text;
    try {
      text = await decodePlaylistBytes(Uint8List.fromList(bytes), legacy: legacyDecoder);
    } on FormatException catch (e) {
      return IptvImportResult(IptvImportStatus.invalid, error: e);
    }
    final parsed = parsePlaylist(text, format);
    if (parsed.truncated) return IptvImportResult(IptvImportStatus.invalid, issues: parsed.issues);
    if (parsed.entries.isEmpty) return IptvImportResult(IptvImportStatus.unsupportedFormat, issues: parsed.issues);
    return await _serial(() async {
      File? staged;
      var committed = false;
      try {
        final IptvPlaylist? existing;
        if (expected != null) {
          existing = await library.playlist(expected.id);
          if (existing != expected) return IptvImportResult(IptvImportStatus.stale);
        } else if (isHot) {
          existing = await library.playlist(IptvPlaylist.hotId);
        } else {
          final matches = [
            for (final playlist in await library.playlists())
              if (!playlist.isHot && playlist.name.trim().toLowerCase() == cleanName.toLowerCase()) playlist,
          ];
          if (matches.length > 1) {
            final byUrl = [
              for (final playlist in matches)
                if (url.isNotEmpty && playlist.source == url) playlist,
            ];
            if (byUrl.length != 1) {
              return IptvImportResult(IptvImportStatus.failed, error: 'Several saved playlists share this name');
            }
            existing = byUrl.single;
          } else {
            existing = matches.firstOrNull;
          }
        }
        if (existing != null && !isHot && !force && !(await confirmReplace?.call(cleanName) ?? false)) {
          return IptvImportResult(IptvImportStatus.cancelled);
        }
        final id = existing?.id ?? (isHot ? IptvPlaylist.hotId : newId());
        if (url.isEmpty) {
          await playlistDirectory.create(recursive: true);
          staged = File(p.join(playlistDirectory.path, 'playlist_${newId()}${format.extension}'));
          await staged.writeAsBytes(bytes, flush: true);
        }
        final source = url.isEmpty ? staged!.path : url;
        final time = now();
        final channels = reconcileChannels(
          playlistId: id,
          previous: await library.channels(id),
          incoming: parsed.entries,
          newId: newId,
        );
        final playlist =
            existing?.copyWith(name: cleanName, format: format, source: source, lastRefresh: time) ??
            IptvPlaylist(
              id: id,
              name: cleanName,
              format: format,
              source: source,
              lastRefresh: time,
              createdAt: time,
              autoUpdate: url.isNotEmpty && autoSyncEnabled(),
            );
        final sourceId = selectedGuideSourceId();
        final mappings = rebuildMappings(
          playlistId: id,
          sourceId: sourceId,
          channels: channels,
          guideChannels: sourceId.isEmpty ? const [] : await library.guideChannels(sourceId),
          previous: await library.mappings(id),
        );
        await library.savePlaylist(playlist, channels, expected: existing, mappings: mappings);
        committed = true;
        if (existing != null && existing.source != source) await _deleteOwnedCopy(existing);
        return IptvImportResult(IptvImportStatus.imported, id: id, issues: parsed.issues);
      } on AmbiguousChannelIdentity catch (e) {
        return IptvImportResult(IptvImportStatus.invalid, error: e);
      } on StaleIptvSnapshot catch (e) {
        return IptvImportResult(IptvImportStatus.stale, error: e);
      } on Object catch (e) {
        return IptvImportResult(IptvImportStatus.failed, error: e);
      } finally {
        if (!committed && staged != null) await _tryDelete(staged);
      }
    });
  }

  /// Downloads and imports the playlist at [url] (3.x `importFromNetworkUrl`):
  /// `#EXTM3U` content is M3U, a `,#genre#` line or a `.txt` path is TXT, a
  /// `.m3u`/`.m3u8` path is M3U, anything else is not a playlist. [name]
  /// defaults to the last path segment without extensions.
  Future<IptvImportResult> importPlaylistFromUrl(
    String url, {
    String? name,
    bool isHot = false,
    bool force = false,
    IptvReplaceConfirm? confirmReplace,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !isHttpUrl(url)) return IptvImportResult(IptvImportStatus.invalid, error: 'Not an http URL');
    final List<int> bytes;
    try {
      bytes = await _download(uri);
    } on Object catch (e) {
      return IptvImportResult(IptvImportStatus.networkFailed, error: e);
    }
    final String text;
    try {
      text = await decodePlaylistBytes(Uint8List.fromList(bytes), legacy: legacyDecoder);
    } on FormatException catch (e) {
      return IptvImportResult(IptvImportStatus.invalid, error: e);
    }
    final format = detectPlaylistFormat(text, path: uri.path);
    if (format == null) return IptvImportResult(IptvImportStatus.unsupportedFormat);
    return await importPlaylist(
      bytes: bytes,
      format: format,
      name: baseName(name ?? uri.path),
      url: url.trim(),
      isHot: isHot,
      force: force,
      confirmReplace: confirmReplace,
    );
  }

  /// Imports pasted or received playlist [text] as [name] (3.x
  /// `importFromWebString`): `#EXTM3U` is M3U, a `.txt` name or a
  /// `,#genre#` line is TXT, anything else M3U. A copy is kept.
  Future<IptvImportResult> importPlaylistText(
    String text,
    String name, {
    bool force = false,
    IptvReplaceConfirm? confirmReplace,
  }) async {
    final format = text.trim().startsWith('#EXTM3U')
        ? IptvPlaylistFormat.m3u
        : name.toLowerCase().endsWith('.txt') || text.contains(',#genre#')
        ? IptvPlaylistFormat.txt
        : IptvPlaylistFormat.m3u;
    return await importPlaylist(
      bytes: utf8.encode(text),
      format: format,
      name: baseName(name),
      force: force,
      confirmReplace: confirmReplace,
    );
  }

  /// Imports a local `.m3u`, `.m3u8` or `.txt` [file] (3.x picker and share
  /// imports); [name] defaults to the file name without extensions.
  Future<IptvImportResult> importPlaylistFile(
    File file, {
    String? name,
    bool force = false,
    IptvReplaceConfirm? confirmReplace,
  }) async {
    final format = IptvPlaylistFormat.fromPath(file.path);
    if (format == null) return IptvImportResult(IptvImportStatus.unsupportedFormat);
    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException catch (e) {
      return IptvImportResult(IptvImportStatus.failed, error: e);
    }
    return await importPlaylist(
      bytes: bytes,
      format: format,
      name: name ?? baseName(file.path),
      force: force,
      confirmReplace: confirmReplace,
    );
  }

  /// Re-reads saved [playlist] from its source and replaces its channels
  /// (3.x `IptvSyncEngine.syncPlaylist`). Network sources are read as bytes
  /// like an import (3.x read them as UTF-8 text, garbling GBK lists); an
  /// M3U source must start with `#EXTM3U` and a TXT source must hold a
  /// comma.
  Future<IptvImportResult> syncPlaylist(IptvPlaylist playlist) async {
    final source = playlist.source.trim();
    if (source.isEmpty) return IptvImportResult(IptvImportStatus.invalid, error: 'Playlist has no source');
    final List<int> bytes;
    if (playlist.isRemote) {
      try {
        bytes = await _download(Uri.parse(source));
      } on Object catch (e) {
        return IptvImportResult(IptvImportStatus.networkFailed, error: e);
      }
      final String text;
      try {
        text = (await decodePlaylistBytes(Uint8List.fromList(bytes), legacy: legacyDecoder)).trim();
      } on FormatException catch (e) {
        return IptvImportResult(IptvImportStatus.invalid, error: e);
      }
      final valid = playlist.format == IptvPlaylistFormat.txt ? text.contains(',') : text.startsWith('#EXTM3U');
      if (text.isEmpty || !valid) return IptvImportResult(IptvImportStatus.unsupportedFormat);
    } else {
      try {
        bytes = await _localFile(source).readAsBytes();
      } on FileSystemException catch (e) {
        return IptvImportResult(IptvImportStatus.failed, error: e);
      }
    }
    return await importPlaylist(
      bytes: bytes,
      format: playlist.format,
      name: playlist.name,
      url: playlist.isRemote ? source : '',
      isHot: playlist.isHot,
      force: true,
      expected: playlist,
    );
  }

  /// Deletes saved [expected] with its channels and its kept copy; false
  /// when it changed meanwhile.
  Future<bool> deletePlaylist(IptvPlaylist expected) => _serial(() async {
    if (!await library.deletePlaylist(expected)) return false;
    await _deleteOwnedCopy(expected);
    return true;
  });

  /// Imports the built-in hot playlist behind the recommendations; calls
  /// while one runs share it.
  Future<void> loadHotPlaylist() => _hotLoad ??= importPlaylistFromUrl(
    hotPlaylistUrl,
    name: hotName,
    isHot: true,
    force: true,
  ).then<void>((_) {}).whenComplete(() => _hotLoad = null);

  // Guides ------------------------------------------------------------------

  /// Imports guide [bytes] (XMLTV, gzip or not, or JSON) as [name]; [source]
  /// is its URL or file path. [expected] makes this a sync.
  Future<IptvImportResult> importGuide({
    required List<int> bytes,
    required String name,
    required String source,
    bool force = false,
    EpgSource? expected,
    IptvReplaceConfirm? confirmReplace,
  }) async {
    final cleanName = name.trim();
    final ParsedGuide parsed;
    try {
      parsed = parseGuide(decodeGuideBytes(bytes));
    } on FormatException catch (e) {
      return IptvImportResult(IptvImportStatus.invalid, error: e);
    }
    if (parsed.isEmpty) return IptvImportResult(IptvImportStatus.unsupportedFormat);
    return await _serial(() async {
      try {
        final List<EpgSource> matched;
        if (expected != null) {
          final current = await library.guideSource(expected.id);
          if (current != expected) return IptvImportResult(IptvImportStatus.stale);
          matched = [current!];
        } else {
          matched = [
            for (final source in await library.guideSources())
              if (source.name.trim().toLowerCase() == cleanName.toLowerCase()) source,
          ];
        }
        if (matched.isNotEmpty && !force && !(await confirmReplace?.call(cleanName) ?? false)) {
          return IptvImportResult(IptvImportStatus.cancelled);
        }
        final existing = matched.firstOrNull;
        final id = existing?.id ?? newId();
        final time = now();
        final channels = <String, EpgChannel>{
          for (final channel in parsed.channels)
            channel.id: EpgChannel(
              sourceId: id,
              channelId: channel.id,
              displayName: channel.primaryName,
              iconUrl: channel.iconUrl,
            ),
        };
        final programmes = [
          for (final programme in parsed.programmes)
            if (programme.channelId.isNotEmpty && programme.title.isNotEmpty) programme.inSource(id),
        ];
        final saved =
            existing?.copyWith(name: cleanName, source: source, lastRefresh: time) ??
            EpgSource(id: id, name: cleanName, source: source, lastRefresh: time, createdAt: time);
        await library.saveGuide(
          saved,
          channels.values.toList(),
          programmes,
          expected: existing,
          duplicates: matched.skip(1).toList(),
        );
        await library.pruneProgrammes(time.subtract(programmeRetention));
        return IptvImportResult(IptvImportStatus.imported, id: id);
      } on StaleIptvSnapshot catch (e) {
        return IptvImportResult(IptvImportStatus.stale, error: e);
      } on Object catch (e) {
        return IptvImportResult(IptvImportStatus.failed, error: e);
      }
    });
  }

  /// Downloads and imports the guide at [url]; [name] defaults to the last
  /// path segment without extensions.
  Future<IptvImportResult> importGuideFromUrl(
    String url, {
    String? name,
    bool force = false,
    IptvReplaceConfirm? confirmReplace,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !isHttpUrl(url)) return IptvImportResult(IptvImportStatus.invalid, error: 'Not an http URL');
    final List<int> bytes;
    try {
      bytes = await _download(uri, headers: const {'user-agent': guideUserAgent});
    } on Object catch (e) {
      return IptvImportResult(IptvImportStatus.networkFailed, error: e);
    }
    return await importGuide(
      bytes: bytes,
      name: baseName(name ?? uri.path),
      source: url.trim(),
      force: force,
      confirmReplace: confirmReplace,
    );
  }

  /// Imports a local `.xml`, `.gz` or `.json` guide [file].
  Future<IptvImportResult> importGuideFile(
    File file, {
    String? name,
    bool force = false,
    IptvReplaceConfirm? confirmReplace,
  }) async {
    final extension = p.extension(file.path).toLowerCase();
    if (!const {'.xml', '.gz', '.json'}.contains(extension)) {
      return IptvImportResult(IptvImportStatus.unsupportedFormat);
    }
    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException catch (e) {
      return IptvImportResult(IptvImportStatus.failed, error: e);
    }
    return await importGuide(
      bytes: bytes,
      name: name ?? baseName(file.path),
      source: file.path,
      force: force,
      confirmReplace: confirmReplace,
    );
  }

  /// Re-reads saved guide [source] (3.x `EpgSyncEngine.updateEpgCache`).
  Future<IptvImportResult> syncGuide(EpgSource source) async {
    final location = source.source.trim();
    if (location.isEmpty) return IptvImportResult(IptvImportStatus.invalid, error: 'Guide has no source');
    final List<int> bytes;
    try {
      bytes = source.isRemote
          ? await _download(Uri.parse(location), headers: const {'user-agent': guideUserAgent})
          : await _localFile(location).readAsBytes();
    } on FileSystemException catch (e) {
      return IptvImportResult(IptvImportStatus.failed, error: e);
    } on Object catch (e) {
      return IptvImportResult(IptvImportStatus.networkFailed, error: e);
    }
    return await importGuide(bytes: bytes, name: source.name, source: location, force: true, expected: source);
  }

  /// Deletes saved guide [expected] with its data; false when it changed.
  Future<bool> deleteGuide(EpgSource expected) => _serial(() => library.deleteGuideSource(expected));

  /// Imports the default guide, then returns the first guide source, which
  /// the caller selects when none is selected (3.x
  /// `loadDefaultEpgResources`). Calls while one runs share it.
  Future<EpgSource?> loadDefaultGuide() => _guideLoad ??= () async {
    await importGuideFromUrl(defaultGuideUrl, name: hotName, force: true);
    return (await library.guideSources()).firstOrNull;
  }().whenComplete(() => _guideLoad = null);

  // Automatic sync ----------------------------------------------------------

  /// [hours] within the allowed interval.
  static int normalizeAutoSyncHours(int hours) => hours.clamp(minAutoSyncHours, maxAutoSyncHours);

  /// Syncs every network playlist and guide with automatic sync on whose
  /// last refresh is older than [hours] (3.x `checkAndExecuteAutoSync`;
  /// the caller checks the global switch). Returns the results in order.
  Future<List<IptvImportResult>> syncExpired({required int hours}) async {
    final threshold = now().subtract(Duration(hours: normalizeAutoSyncHours(hours)));
    bool due({required bool remote, required bool auto, DateTime? last}) =>
        remote && auto && last != null && last.isBefore(threshold);
    final results = <IptvImportResult>[];
    for (final playlist in await library.playlists()) {
      if (due(remote: playlist.isRemote, auto: playlist.autoUpdate, last: playlist.lastRefresh)) {
        results.add(await syncPlaylist(playlist));
      }
    }
    for (final source in await library.guideSources()) {
      if (due(remote: source.isRemote, auto: source.autoUpdate, last: source.lastRefresh)) {
        results.add(await syncGuide(source));
      }
    }
    return results;
  }

  // Helpers -----------------------------------------------------------------

  Future<List<int>> _download(Uri url, {Map<String, String> headers = const {}}) async {
    final response = await http.send(LiveRequest.get(site: site, url: url, headers: headers, timeout: downloadTimeout));
    if (!response.isSuccess) throw HttpStatusFailure.of(site, response);
    return response.bytes;
  }

  static File _localFile(String source) {
    final uri = Uri.tryParse(source);
    return uri != null && uri.scheme == 'file' ? File.fromUri(uri) : File(source);
  }

  static final RegExp _ownedCopy = RegExp(r'^playlist_[0-9a-f-]{36}\.(m3u8?|txt)$', caseSensitive: false);
  static final RegExp _legacyId = RegExp(r'^[0-9a-f-]+$', caseSensitive: false);

  /// Deletes the copy of [playlist] kept in [playlistDirectory] when no
  /// saved playlist refers to it any more; files elsewhere (3.x kept some
  /// external paths) are never touched.
  Future<void> _deleteOwnedCopy(IptvPlaylist playlist) async {
    if (playlist.isRemote) return;
    final candidate = _localFile(playlist.source).path;
    if (!p.equals(p.dirname(p.absolute(candidate)), p.absolute(playlistDirectory.path))) return;
    final name = p.basename(candidate);
    final legacy =
        _legacyId.hasMatch(playlist.id) && const ['.m3u', '.m3u8', '.txt'].any((ext) => name == '${playlist.id}$ext');
    if (!_ownedCopy.hasMatch(name) && !legacy) return;
    for (final other in await library.playlists()) {
      if (!other.isRemote && p.equals(p.absolute(_localFile(other.source).path), p.absolute(candidate))) return;
    }
    await _tryDelete(File(candidate));
  }

  static Future<void> _tryDelete(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Cleanup is best effort; a leftover copy is harmless.
    }
  }

  /// [path]'s last segment without any extension (`a/b.m3u8` → `b`).
  static String baseName(String path) {
    var name = p.basename(path.trim());
    while (p.extension(name).isNotEmpty) {
      name = p.basenameWithoutExtension(name);
    }
    return name;
  }
}
