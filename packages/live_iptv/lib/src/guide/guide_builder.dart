import 'package:live_iptv/src/model.dart';
import 'package:meta/meta.dart';

/// Collects guide channels and programmes from any format and applies the
/// shared rules (spec/modules/iptv.md §2): channels are unique by id (names
/// merged), a programme without a stop ends at its channel's next start,
/// programmes with a bad time or no title are skipped, programmes outside
/// the window are dropped, and one programme per channel and start is kept.
@internal
final class GuideBuilder {
  /// Keeps programmes overlapping [from]..[to] (either end open when null).
  new({this.from, this.to});

  /// Window start.
  final DateTime? from;

  /// Window end.
  final DateTime? to;

  final _channels = <String, IptvGuideChannel>{};
  final _programmes = <_Pending>[];
  final _issues = <String, int>{};

  /// Records a skipped item.
  void issue(String reason) => _issues[reason] = (_issues[reason] ?? 0) + 1;

  /// Adds or merges a channel.
  void channel(String? id, List<String> names, String? icon) {
    if (id == null || id.isEmpty) {
      issue('Channel without an id');
      return;
    }
    final existing = _channels[id];
    _channels[id] = existing == null
        ? IptvGuideChannel(id: id, names: List.unmodifiable(names), icon: icon)
        : IptvGuideChannel(
            id: id,
            names: List.unmodifiable({...existing.names, ...names}),
            icon: existing.icon ?? icon,
          );
  }

  /// Adds a programme; [stop] may be null when [hasStop] is false.
  void programme({
    required String? channelId,
    required DateTime? start,
    required DateTime? stop,
    required String? title,
    bool hasStop = true,
    String? subtitle,
    String? description,
    String? catchupId,
  }) {
    final reason = switch ((channelId, title, start)) {
      (null || '', _, _) => 'Programme without a channel',
      (_, null, _) => 'Programme without a title',
      (_, final String text, _) when text.trim().isEmpty => 'Programme without a title',
      (_, _, null) => 'Programme with an invalid time',
      _ when hasStop && stop == null => 'Programme with an invalid time',
      _ => null,
    };
    if (reason != null) {
      issue(reason);
      return;
    }
    _programmes.add(
      _Pending(
        channelId: channelId!,
        start: start!.toUtc(),
        stop: stop?.toUtc(),
        title: title!.trim(),
        subtitle: subtitle,
        description: description,
        catchupId: catchupId,
      ),
    );
  }

  /// The parsed guide.
  ParsedGuide build() {
    final byChannel = <String, List<_Pending>>{};
    for (final programme in _programmes) {
      byChannel.putIfAbsent(programme.channelId, () => []).add(programme);
    }
    final programmes = <IptvProgramme>[];
    for (final MapEntry(key: channelId, value: list) in byChannel.entries) {
      list.sort((a, b) => a.start.compareTo(b.start));
      DateTime? lastStart;
      for (var i = 0; i < list.length; i++) {
        final item = list[i];
        if (item.start == lastStart) {
          issue('Duplicate programme');
          continue;
        }
        lastStart = item.start;
        final stop = item.stop ?? (i + 1 < list.length ? list[i + 1].start : null);
        if (stop == null || !stop.isAfter(item.start)) {
          issue('Programme with an invalid time');
          continue;
        }
        if ((from != null && !stop.isAfter(from!)) || (to != null && !item.start.isBefore(to!))) continue;
        programmes.add(
          IptvProgramme(
            channelId: channelId,
            start: item.start,
            stop: stop,
            title: item.title,
            subtitle: item.subtitle,
            description: item.description,
            catchupId: item.catchupId,
          ),
        );
      }
    }
    // Programmes may name channels the guide never declares; they can still
    // be matched by id.
    for (final id in byChannel.keys) {
      _channels.putIfAbsent(id, () => IptvGuideChannel(id: id));
    }
    return ParsedGuide(
      channels: [..._channels.values],
      programmes: programmes,
      issues: [
        for (final MapEntry(key: reason, value: count) in _issues.entries)
          IptvIssue(count == 1 ? reason : '$reason ($count)'),
      ],
    );
  }
}

final class _Pending {
  const new({
    required this.channelId,
    required this.start,
    required this.stop,
    required this.title,
    this.subtitle,
    this.description,
    this.catchupId,
  });

  final String channelId;
  final DateTime start;
  final DateTime? stop;
  final String title;
  final String? subtitle;
  final String? description;
  final String? catchupId;
}
