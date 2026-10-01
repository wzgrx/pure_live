import 'package:live_iptv/src/model.dart';

final RegExp _nonWord = RegExp('[^a-zA-Z0-9\u4e00-\u9fa5]');

/// Unique-only matching of playlist channels to the channels of one guide,
/// used when a playlist is imported (3.x `_ImportEpgIndex`): the answer never
/// depends on row order — a key that fits several guide channels matches
/// none.
///
/// Steps: `tvg-id` equals a guide id (case-insensitive); the channel id
/// equals a guide id (3.x's older channel ids); the name equals a guide
/// name (lower case, only letters, digits and CJK); one guide name contains
/// the name or is contained in it.
final class GuideIndex {
  /// Indexes [channels] (all of one source).
  new(Iterable<EpgChannel> channels) {
    for (final channel in channels) {
      final id = channel.channelId.trim().toLowerCase();
      if (id.isNotEmpty) (_byId[id] ??= []).add(channel.key);
      final name = _name(channel.displayName);
      if (name.isNotEmpty) (_byName[name] ??= []).add(channel.key);
    }
  }

  final _byId = <String, List<String>>{};
  final _byName = <String, List<String>>{};
  final _nameMatches = <String, String?>{};

  static String _name(String value) => value.toLowerCase().replaceAll(_nonWord, '');

  static String? _unique(List<String> keys) => keys.length == 1 ? keys.single : null;

  /// The guide channel key for [channel], or null.
  String? match(IptvChannel channel) {
    final tvgId = channel.entry.tvgId?.trim().toLowerCase();
    if (tvgId != null && _byId[tvgId] != null) return _unique(_byId[tvgId]!);
    if (_byId[channel.id.trim().toLowerCase()] case final legacy?) return _unique(legacy);
    final name = _name(channel.name);
    if (name.isEmpty) return null;
    if (_nameMatches.containsKey(name)) return _nameMatches[name];
    if (_byName[name] case final exact?) return _nameMatches[name] = _unique(exact);
    String? found;
    for (final MapEntry(:key, :value) in _byName.entries) {
      if (name.contains(key) || key.contains(name)) {
        if (found != null || value.length != 1) return _nameMatches[name] = null;
        found = value.single;
      }
    }
    return _nameMatches[name] = found;
  }
}

/// The mapping changes for playlist [playlistId] against guide source
/// [sourceId] (3.x `_rebuildEpgMappings`): locked and hand-made mappings are
/// kept, automatic ones follow [GuideIndex], and automatic ones that no
/// longer match are deleted. Without channels or guide channels nothing
/// changes (missing data is no reason to drop saved mappings).
({List<EpgMapping> upserts, List<EpgMapping> deletes}) rebuildMappings({
  required String playlistId,
  required String sourceId,
  required List<IptvChannel> channels,
  required List<EpgChannel> guideChannels,
  required List<EpgMapping> previous,
}) {
  if (sourceId.isEmpty || channels.isEmpty || guideChannels.isEmpty) return (upserts: const [], deletes: const []);
  final byChannel = {for (final mapping in previous) mapping.channelId: mapping};
  final index = GuideIndex(guideChannels);
  final matched = <String>{};
  final upserts = <EpgMapping>[];
  for (final channel in channels) {
    final old = byChannel[channel.id];
    if (old != null && (old.locked || old.origin != EpgMapping.autoOrigin)) continue;
    final key = index.match(channel);
    if (key == null) continue;
    matched.add(channel.id);
    if (old?.epgChannelKey == key && old?.epgSourceId == sourceId) continue;
    upserts.add(EpgMapping(channelId: channel.id, playlistId: playlistId, epgChannelKey: key, epgSourceId: sourceId));
  }
  final deletes = [
    for (final old in previous)
      if (!old.locked && old.origin == EpgMapping.autoOrigin && !matched.contains(old.channelId)) old,
  ];
  return (upserts: upserts, deletes: deletes);
}

/// The guide channel key a room of [channel] shows programmes from (3.x
/// `IptvSite._resolveEpgChannelId`), or null:
///
/// 1. a saved [mapping] to [sourceId] that still resolves (a locked one is
///    final even when its channel is gone);
/// 2. the first guide channel whose id equals `tvg-id` (case-insensitive);
/// 3. by name: the first word of the name and of each guide name, lower
///    case, only letters, digits and CJK, without `综合 高清 超清 中央 电视台
///    频道 hd`; candidates contain one another, an equal name wins, then the
///    best fuzzy score. Empty normalized names never match (3.x matched
///    every guide channel then).
String? resolveGuideChannel({
  required IptvChannel channel,
  required String sourceId,
  required List<EpgChannel> guideChannels,
  EpgMapping? mapping,
}) {
  if (sourceId.isEmpty) return null;
  if (mapping != null && mapping.epgSourceId == sourceId) {
    final resolved = resolveGuideReference(sourceId, mapping.epgChannelKey, guideChannels);
    if (resolved != null || mapping.locked) return resolved;
  }
  if (guideChannels.isEmpty) return null;
  final tvgId = channel.entry.tvgId?.trim().toLowerCase();
  if (tvgId != null && tvgId.isNotEmpty) {
    for (final guide in guideChannels) {
      if (guide.channelId.trim().toLowerCase() == tvgId) return guide.key;
    }
  }
  final target = _roomName(channel.name);
  if (target.isEmpty) return null;
  final candidates = [
    for (final guide in guideChannels)
      if (_roomName(guide.displayName) case final name
          when name.isNotEmpty && (target.contains(name) || name.contains(target)))
        (guide: guide, name: name),
  ];
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    final aPerfect = a.name == target;
    final bPerfect = b.name == target;
    if (aPerfect != bPerfect) return aPerfect ? -1 : 1;
    if (aPerfect) return 0;
    return fuzzyScore(channel.name, b.guide.displayName).compareTo(fuzzyScore(channel.name, a.guide.displayName));
  });
  return candidates.first.guide.key;
}

/// The key of the guide channel [reference] names inside source
/// [sourceId]: a key, or a raw guide id (3.x rooms and mappings from before
/// keys) when exactly one channel has it (3.x `resolveEpgChannelId`).
String? resolveGuideReference(String sourceId, String reference, Iterable<EpgChannel> guideChannels) {
  final matches = [
    for (final guide in guideChannels)
      if (guide.sourceId == sourceId && (guide.key == reference || guide.channelId == reference)) guide,
  ];
  for (final guide in matches) {
    if (guide.key == reference) return guide.key;
  }
  return matches.length == 1 ? matches.single.key : null;
}

final RegExp _roomSuffix = RegExp('(综合|高清|超清|中央|电视台|频道|hd)', caseSensitive: false);

String _roomName(String value) =>
    value.trim().split(' ').first.toLowerCase().replaceAll(_nonWord, '').replaceAll(_roomSuffix, '').trim();

/// 3.x `fuzzyMatch`: each word of [query] scores 1 when [text] contains it
/// and 0.5 when a word of [text] is more than 60 % similar (Dice
/// coefficient over letter pairs); any other word makes the score 0.
double fuzzyScore(String query, String text) {
  final split = RegExp(r'[\s,|]+');
  final tokens = query.toLowerCase().split(split).where((token) => token.isNotEmpty).toList();
  if (tokens.isEmpty) return 0;
  final blob = text.toLowerCase();
  final words = blob.split(split).where((word) => word.isNotEmpty).toList();
  var score = 0.0;
  for (final token in tokens) {
    if (blob.contains(token)) {
      score += 1;
      continue;
    }
    var best = 0.0;
    for (final word in words) {
      final similarity = diceCoefficient(token, word);
      if (similarity > best) best = similarity;
    }
    if (best <= 0.6) return 0;
    score += 0.5;
  }
  return score;
}

/// Dice's coefficient of the letter pairs of [a] and [b], whitespace
/// removed (`string_similarity`'s `compareTwoStrings`, which 3.x used).
double diceCoefficient(String a, String b) {
  final first = a.replaceAll(RegExp(r'\s+'), '');
  final second = b.replaceAll(RegExp(r'\s+'), '');
  if (first == second) return 1;
  if (first.length < 2 || second.length < 2) return 0;
  final pairs = <String, int>{};
  for (var i = 0; i < first.length - 1; i++) {
    final pair = first.substring(i, i + 2);
    pairs[pair] = (pairs[pair] ?? 0) + 1;
  }
  var shared = 0;
  for (var i = 0; i < second.length - 1; i++) {
    final pair = second.substring(i, i + 2);
    final count = pairs[pair] ?? 0;
    if (count > 0) {
      pairs[pair] = count - 1;
      shared++;
    }
  }
  return 2 * shared / (first.length + second.length - 2);
}
