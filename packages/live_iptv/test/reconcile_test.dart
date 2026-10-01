import 'package:live_iptv/live_iptv.dart';
import 'package:test/test.dart';

/// Main cases of 3.x `iptv_import_manager_test.dart` that concern ids.
void main() {
  var ids = 0;
  String newId() => 'new-${++ids}';
  IptvEntry entry(String name, String url, {String? tvgId, String? group}) =>
      IptvEntry(name: name, streamUrl: url, tvgId: tvgId, groupTitle: group);
  IptvChannel saved(String id, IptvEntry entry, {bool autoUpdate = true}) =>
      IptvChannel(id: id, playlistId: 'p', entry: entry, autoUpdate: autoUpdate);

  setUp(() => ids = 0);

  test('ids follow rotating tokens, renamed channels and reordering; duplicates merge', () {
    final previous = [
      saved('a', entry('CCTV-1', 'http://f/1?token=old', tvgId: 'cctv1')),
      saved('b', entry('Old name', 'http://f/2')),
      saved('c', entry('Same', 'http://f/3a', group: 'G1')),
      saved('d', entry('Same', 'http://f/3b', group: 'G2')),
    ];
    final result = reconcileChannels(
      playlistId: 'p',
      previous: previous,
      newId: newId,
      incoming: [
        entry('Same', 'http://f/3b', group: 'G2'),
        entry('CCTV-1 HD', 'http://f/1?token=new', tvgId: 'CCTV1'),
        entry('New name', 'http://f/2'),
        entry('Same', 'http://f/3a', group: 'G1'),
        entry('Same', 'http://f/3a', group: 'G1'),
        entry('Fresh', 'http://f/4'),
      ],
    );
    expect(result.map((c) => (c.id, c.name)), [
      ('d', 'Same'),
      ('a', 'CCTV-1 HD'),
      ('b', 'New name'),
      ('c', 'Same'),
      ('new-1', 'Fresh'),
    ]);
  });

  test('different tvg-ids never share an id; an ambiguous rotation keeps the old list', () {
    final conflict = reconcileChannels(
      playlistId: 'p',
      previous: [saved('a', entry('X', 'http://f/x', tvgId: 'one'))],
      incoming: [entry('Y', 'http://f/x', tvgId: 'two')],
      newId: newId,
    );
    expect(conflict.single.id, 'new-1');
    expect(
      () => reconcileChannels(
        playlistId: 'p',
        previous: [saved('a', entry('Multi', 'http://f/1')), saved('b', entry('Multi', 'http://f/2'))],
        incoming: [entry('Multi', 'http://f/3'), entry('Multi', 'http://f/4')],
        newId: newId,
      ),
      throwsA(isA<AmbiguousChannelIdentity>()),
    );
  });

  test('a channel with auto update off keeps every field', () {
    final kept = saved('a', entry('Mine', 'http://f/old'), autoUpdate: false);
    final result = reconcileChannels(playlistId: 'p', previous: [kept], incoming: [entry('Mine', 'http://f/new')]);
    expect(identical(result.single, kept), isTrue);
  });
}
