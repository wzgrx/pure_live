import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:pure_live/app/iptv_library.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The importer of the page (tests replace it); null when IPTV is not set
/// up.
final Provider<IptvImporter?> iptvImporterProvider = Provider<IptvImporter?>(
  (ref) => ref.watch(appServicesProvider).iptvImporter,
);

/// The page's clock, for "updated at" texts (tests replace it).
final Provider<DateTime Function()> iptvClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The playlists and guides, loaded again after every write to the IPTV
/// tables (an import, a sync, the background auto-sync).
final StreamProvider<IptvOverview> iptvOverviewProvider = StreamProvider.autoDispose<IptvOverview>((ref) {
  final importer = ref.watch(iptvImporterProvider);
  if (importer == null) return Stream.value(const IptvOverview(playlists: [], guides: []));
  return ref.watch(storeProvider).database.watch(IptvTables.all, () => IptvOverview.load(importer.library));
});

/// A saved playlist with its channel count.
typedef IptvPlaylistInfo = ({IptvPlaylist playlist, int channels});

/// A saved guide source with its channel count.
typedef IptvGuideInfo = ({EpgSource source, int channels});

/// What the page shows: the playlists (the built-in hot list last) and the
/// guide sources, in import order.
@immutable
final class IptvOverview {
  /// Creates an overview.
  const new({required this.playlists, required this.guides});

  /// Reads [library].
  static Future<IptvOverview> load(IptvLibrary library) async {
    final playlists = <IptvPlaylistInfo>[
      for (final playlist in await library.playlists())
        (playlist: playlist, channels: (await library.channels(playlist.id)).length),
    ]..sort((a, b) => (a.playlist.isHot ? 1 : 0).compareTo(b.playlist.isHot ? 1 : 0));
    final guides = <IptvGuideInfo>[
      for (final source in await library.guideSources())
        (source: source, channels: (await library.guideChannels(source.id)).length),
    ];
    return IptvOverview(playlists: playlists, guides: guides);
  }

  /// Playlists.
  final List<IptvPlaylistInfo> playlists;

  /// Guide sources.
  final List<IptvGuideInfo> guides;

  /// Channels of all playlists.
  int get channelCount => playlists.fold(0, (sum, info) => sum + info.channels);

  /// Network playlists and guides (the ones a sync downloads again).
  int get networkCount =>
      playlists.where((info) => info.playlist.isRemote).length + guides.where((info) => info.source.isRemote).length;

  /// The guide source [id], or null.
  EpgSource? guide(String id) => guides.map((info) => info.source).where((source) => source.id == id).firstOrNull;
}

/// The format badge of [playlist] (`M3U`, `M3U8`, `TXT`).
String playlistBadge(IptvPlaylist playlist) {
  if (playlist.format == IptvPlaylistFormat.txt) return 'TXT';
  final path = (Uri.tryParse(playlist.source)?.path ?? playlist.source).toLowerCase();
  return path.endsWith('.m3u8') ? 'M3U8' : 'M3U';
}

/// The format badge of [source] by its address (3.x: `XML.GZ`, `JSON`,
/// `XML`; the importer reads the content, so this is only a hint).
String guideBadge(EpgSource source) {
  final path = (Uri.tryParse(source.source)?.path ?? source.source).toLowerCase();
  if (path.endsWith('.gz')) return 'GZ';
  if (path.endsWith('.json')) return 'JSON';
  return 'XML';
}

/// The display name of [playlist]: the built-in list's name `hot` reads as
/// "热门频道".
String playlistName(IptvPlaylist playlist) => playlist.isHot ? i18n('iptv_hot_playlist') : playlist.name;

/// The display name of [source]: the default guide (imported as `hot`)
/// reads as "默认节目单".
String guideName(EpgSource source) => guideDisplayName(source.name, source: source.source);

/// The display name of a guide called [name] at [source].
String guideDisplayName(String name, {String? source}) =>
    name == IptvImporter.hotName && (source == null || source == IptvImporter.defaultGuideUrl)
    ? i18n('iptv_default_guide')
    : name;

/// "Updated today 12:05" / "updated 09-30 12:05" / "never updated".
String updatedText(DateTime? time, DateTime now) {
  if (time == null) return i18n('iptv_never_updated');
  String two(int value) => value.toString().padLeft(2, '0');
  final local = time.toLocal();
  final clock = '${two(local.hour)}:${two(local.minute)}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final text = day == today
      ? i18n('iptv_today_at', args: {'time': clock})
      : local.year == now.year
      ? '${two(local.month)}-${two(local.day)} $clock'
      : '${local.year}-${two(local.month)}-${two(local.day)} $clock';
  return i18n('iptv_updated_at', args: {'time': text});
}

/// The message of a failed import or sync, or null when there is nothing
/// to say ([IptvImportStatus.imported], [IptvImportStatus.cancelled]).
String? failureText(IptvImportResult result, {required bool guide}) => switch (result.status) {
  IptvImportStatus.imported || IptvImportStatus.cancelled => null,
  IptvImportStatus.unsupportedFormat => i18n(guide ? 'iptv_unsupported_guide' : 'iptv_unsupported_playlist'),
  IptvImportStatus.invalid => i18n('iptv_invalid_content'),
  IptvImportStatus.networkFailed => i18n('iptv_download_failed'),
  IptvImportStatus.stale => i18n('iptv_changed_meanwhile'),
  IptvImportStatus.failed => i18n('iptv_save_failed'),
};
