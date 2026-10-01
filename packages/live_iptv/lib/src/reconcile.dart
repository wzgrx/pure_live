import 'dart:convert';

import 'package:live_iptv/src/model.dart';

/// Thrown when a sync cannot tell which saved channel a new line continues;
/// the saved playlist is kept (3.x threw the same `StateError`).
final class AmbiguousChannelIdentity implements Exception {
  /// Creates the error.
  const new();

  @override
  String toString() => 'Ambiguous playlist channel identities; previous playlist preserved';
}

/// The channels of playlist [playlistId] after a sync: each line of
/// [incoming] keeps the id of the saved channel it continues, so follows,
/// rooms and guide mappings survive (3.x `reconcilePlaylistChannels`).
///
/// Identical lines are merged. A line continues a saved channel only on a
/// unique match, tried from the strongest key to the weakest: tvg-id + URL +
/// group, name + URL + group, tvg-id + URL, name + URL, tvg-id, name +
/// group, name, URL; two different tvg-ids never match. When a leftover line
/// could still belong to a leftover saved channel, the sync stops with
/// [AmbiguousChannelIdentity] rather than guess. Saved channels with
/// `autoUpdate` off keep every field. New lines get ids from [newId].
List<IptvChannel> reconcileChannels({
  required String playlistId,
  required List<IptvChannel> previous,
  required List<IptvEntry> incoming,
  String Function() newId = randomUuid,
}) {
  final unique = <String, IptvEntry>{};
  for (final entry in incoming) {
    unique.putIfAbsent(entry.contentKey, () => entry);
  }
  final entries = unique.values.toList();
  final matched = <int, IptvChannel>{};
  final used = <String>{};
  for (var phase = 0; phase < 8; phase++) {
    final oldKeys = <String, List<IptvChannel>>{};
    final newKeys = <String, List<int>>{};
    for (final old in previous) {
      if (used.contains(old.id)) continue;
      if (_key(phase, old.entry) case final key?) (oldKeys[key] ??= []).add(old);
    }
    for (var i = 0; i < entries.length; i++) {
      if (matched.containsKey(i)) continue;
      if (_key(phase, entries[i]) case final key?) (newKeys[key] ??= []).add(i);
    }
    for (final MapEntry(:key, value: indexes) in newKeys.entries) {
      final old = oldKeys[key];
      if (indexes.length != 1 || old == null || old.length != 1) continue;
      final i = indexes.single;
      final oldTvg = _normalize(old.single.entry.tvgId);
      final newTvg = _normalize(entries[i].tvgId);
      if (oldTvg.isNotEmpty && newTvg.isNotEmpty && oldTvg != newTvg) continue;
      matched[i] = old.single;
      used.add(old.single.id);
    }
  }
  final remainingTvg = <String>{};
  final remainingNames = <String, Set<String>>{};
  final remainingUrls = <String, Set<String>>{};
  for (final old in previous) {
    if (used.contains(old.id)) continue;
    final tvg = _normalize(old.entry.tvgId);
    if (tvg.isNotEmpty) remainingTvg.add(tvg);
    (remainingNames[_normalize(old.name)] ??= {}).add(tvg);
    (remainingUrls[old.streamUrl.trim()] ??= {}).add(tvg);
  }
  for (var i = 0; i < entries.length; i++) {
    if (matched.containsKey(i)) continue;
    final tvg = _normalize(entries[i].tvgId);
    bool plausible(Set<String>? values) =>
        values != null && (tvg.isEmpty || values.contains('') || values.contains(tvg));
    if ((tvg.isNotEmpty && remainingTvg.contains(tvg)) ||
        plausible(remainingNames[_normalize(entries[i].name)]) ||
        plausible(remainingUrls[entries[i].streamUrl.trim()])) {
      throw const AmbiguousChannelIdentity();
    }
  }
  return [
    for (var i = 0; i < entries.length; i++)
      switch (matched[i]) {
        final old? when !old.autoUpdate => old,
        final old? => old.withEntry(entries[i]),
        null => IptvChannel(id: newId(), playlistId: playlistId, entry: entries[i]),
      },
  ];
}

String _normalize(String? value) => value?.trim().toLowerCase() ?? '';

String? _key(int phase, IptvEntry entry) {
  final name = _normalize(entry.name);
  final tvg = _normalize(entry.tvgId);
  final group = _normalize(entry.groupTitle);
  final url = entry.streamUrl.trim();
  return switch (phase) {
    0 => tvg.isEmpty ? null : jsonEncode([tvg, url, group]),
    1 => name.isEmpty ? null : jsonEncode([name, url, group]),
    2 => tvg.isEmpty ? null : jsonEncode([tvg, url]),
    3 => name.isEmpty ? null : jsonEncode([name, url]),
    4 => tvg.isEmpty ? null : tvg,
    5 => name.isEmpty ? null : jsonEncode([name, group]),
    6 => name.isEmpty ? null : name,
    _ => url.isEmpty ? null : url,
  };
}
