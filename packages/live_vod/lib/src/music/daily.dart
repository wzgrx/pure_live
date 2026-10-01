import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_vod/src/models.dart';
import 'package:live_vod/src/store.dart';

/// Daily recommendations from a favourite folder (bmsc's brute-force daily
/// list, pure_live_TV `b9d2f739` `daily_recommendation_service.dart`).
///
/// A day's list: shuffle the folder, take [seedCount] seeds, ask each
/// seed's related videos and keep the first one that is in a music
/// partition ([musicTypes]), at least a minute long and never recommended
/// before. The list is kept for the local day and the folder; a changed
/// folder or [today]`(force: true)` makes a new one. One slot can be
/// re-rolled from a random folder video ([reroll]).
///
/// Changes from the TV service: the "never recommended" history keeps the
/// newest [historyLimit] ids (it grew without bound); the day is the local
/// calendar day of the injected clock; the list cache stores the archives'
/// own shape, not the TV's freezed JSON.
final class DailyRecommender {
  /// Creates the recommender. [folderArchives] lists a folder's playable
  /// archives (deleted ones left out); [related] gives an archive's related
  /// videos.
  new({
    required this.folderArchives,
    required this.related,
    required this.store,
    DateTime Function()? now,
    Random? random,
  }) : _now = now ?? DateTime.now,
       _random = random ?? Random();

  /// A folder's archives.
  final Future<List<VodArchive>> Function(int folderId) folderArchives;

  /// Related videos of an archive.
  final Future<List<VodArchive>> Function(VodArchive seed) related;

  /// Where the list, its date and the history are kept.
  final VodKeyValueStore store;

  final DateTime Function() _now;
  final Random _random;

  /// Partitions counted as music: 130 音乐综合, 193 MV, 267 电台, 28 原创音乐,
  /// 59 演奏 (the reference's whitelist).
  static const Set<int> musicTypes = {130, 193, 267, 28, 59};

  /// Seeds per day.
  static const int seedCount = 30;

  /// Ids kept in the "already recommended" history.
  static const int historyLimit = 2000;

  static const String _listKey = 'music.daily.list';
  static const String _dateKey = 'music.daily.date';
  static const String _folderKey = 'music.daily.folder';
  static const String _historyKey = 'music.daily.history';
  static const String _defaultFolderKey = 'music.daily.defaultFolder';

  /// The folder the list is made from, or null before one is chosen.
  ({int id, String title})? get defaultFolder {
    final decoded = _decode(store.read(_defaultFolderKey));
    if (decoded is! Map) return null;
    final id = jsonInt(decoded['id']) ?? 0;
    return id > 0 ? (id: id, title: jsonString(decoded['title']) ?? '$id') : null;
  }

  /// Chooses the folder.
  Future<void> setDefaultFolder(int id, String title) =>
      store.write(_defaultFolderKey, jsonEncode({'id': id, 'title': title}));

  String _day(DateTime time) {
    final local = time.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  static Object? _decode(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  /// Today's list for the default folder (null when none is chosen or the
  /// folder is empty).
  Future<List<VodArchive>?> today({bool force = false}) async {
    final folder = defaultFolder;
    if (folder == null) return null;
    final sameDay = store.read(_dateKey) == _day(_now());
    final sameFolder = store.read(_folderKey) == '${folder.id}';
    if (!force && sameDay && sameFolder) {
      final cached = cachedList();
      if (cached.isNotEmpty) return cached;
    }
    final archives = await folderArchives(folder.id);
    if (archives.isEmpty) return null;
    final seeds = [...archives]..shuffle(_random);
    final history = _history();
    final picks = await Future.wait([for (final seed in seeds.take(seedCount)) _pick(seed, history)]);
    final list = [...picks.nonNulls];
    await _saveHistory(history);
    await save(list);
    await store.write(_dateKey, _day(_now()));
    await store.write(_folderKey, '${folder.id}');
    return list;
  }

  /// A new pick for one slot, seeded by a random folder video that is not
  /// in [current]; null when nothing fits.
  Future<VodArchive?> reroll(List<VodArchive> current) async {
    final folder = defaultFolder;
    if (folder == null) return null;
    final taken = {for (final archive in current) archive.bvid};
    final candidates = [
      for (final archive in await folderArchives(folder.id))
        if (!taken.contains(archive.bvid)) archive,
    ];
    if (candidates.isEmpty) return null;
    final history = _history()..addAll(taken);
    final pick = await _pick(candidates[_random.nextInt(candidates.length)], history);
    await _saveHistory(history);
    return pick;
  }

  /// The first related video of [seed] that is music, ≥ 60 s and not in
  /// [history] (which it joins). A failed seed loses its slot only.
  Future<VodArchive?> _pick(VodArchive seed, Set<String> history) async {
    List<VodArchive> candidates;
    try {
      candidates = await related(seed);
    } on SiteError {
      return null;
    }
    for (final video in candidates) {
      if (!musicTypes.contains(video.typeId)) continue;
      if (video.duration < const Duration(minutes: 1) || history.contains(video.bvid)) continue;
      history.add(video.bvid);
      return video;
    }
    return null;
  }

  /// The stored list (empty when none).
  List<VodArchive> cachedList() {
    final decoded = _decode(store.read(_listKey));
    return [
      if (decoded is List)
        for (final item in decoded.whereType<Map<String, Object?>>()) VodArchive.fromJson(item),
    ];
  }

  /// Stores [list] as today's (after a re-roll).
  Future<void> save(List<VodArchive> list) =>
      store.write(_listKey, jsonEncode([for (final archive in list) archive.toJson()]));

  Set<String> _history() {
    final decoded = _decode(store.read(_historyKey));
    // Insertion order is kept, so the oldest ids are dropped first.
    return <String>{if (decoded is List) ...decoded.whereType<String>()};
  }

  Future<void> _saveHistory(Set<String> history) async {
    final kept = history.length > historyLimit ? history.skip(history.length - historyLimit) : history;
    await store.write(_historyKey, jsonEncode(kept.toList()));
  }
}
