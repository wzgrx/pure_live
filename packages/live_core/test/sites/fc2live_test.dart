// FC2 Live: parsing, the control socket and the lease-held adapter over the
// recorded samples (spec/sites/fc2live.md). No legacy expected values (ADR 0016).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _channel = '62996200';

/// The recorded control conversation (fixtures/fc2live/control/S04-control).
List<String> _serverMessages() => [
  for (final line in File('../../fixtures/fc2live/control/S04-control/frames.jsonl').readAsLinesSync())
    if (line.trim().isNotEmpty)
      if (jsonDecode(line) case {'dir': 'in', 'text': final String text}) text,
];

/// A socket that replays the recorded server messages once listened to.
final class _ReplaySocket implements TextSocket {
  new(List<String> incoming) {
    _controller = StreamController<String>(
      onListen: () => scheduleMicrotask(() {
        for (final message in incoming) {
          if (!_controller.isClosed) _controller.add(message);
        }
      }),
    );
  }

  late final StreamController<String> _controller;
  final List<String> sent = [];
  bool closed = false;

  @override
  Stream<String> get messages => _controller.stream;

  @override
  void send(String text) {
    if (!closed) sent.add(text);
  }

  /// Server-side close.
  void drop() => unawaited(_controller.close());

  @override
  Future<void> close() async {
    closed = true;
    if (!_controller.isClosed) await _controller.close();
  }
}

Fc2LiveSite _site(
  List<String> samples, {
  required List<_ReplaySocket> sockets,
  List<(Uri, Map<String, String>)>? opened,
}) => Fc2LiveSite(
  ReplayHttp.fixtures('../../fixtures/fc2live', samples),
  connect: (url, headers) async {
    opened?.add((url, headers));
    return sockets.removeAt(0);
  },
);

void main() {
  group('§2 directory', () {
    test('S01 public live channels, busiest first; paid, login and ticket rooms dropped', () {
      final body = Fixture.load('fc2live', 'S01-directory').body;
      final all = Fc2LiveParse.directory(body);
      expect(all, hasLength(56), reason: '63 channels, 7 restricted');
      final page = Fc2LiveParse.page(body);
      expect(page.items.first.ref, RoomRef('fc2live', _channel));
      expect(page.items.first.audience.online, 128);
      expect(page.items.first.area, 'その他');
      expect(page.isLast, isTrue);
      final online = page.items.map((c) => c.audience.online ?? 0).toList();
      expect(online, [...online]..sort((a, b) => b.compareTo(a)));
    });

    test('the site category filters', () {
      final body = Fixture.load('fc2live', 'S01-directory').body;
      expect(Fc2LiveParse.page(body, area: Fc2LiveParse.areas[0]).items, hasLength(21));
      expect(Fc2LiveParse.page(body, area: Fc2LiveParse.areas[1]).items, hasLength(9), reason: 'game and work');
      expect(() => Fc2LiveParse.page('{"link":""}'), throwsA(isA<ApiChanged>()));
    });
  });

  group('§4 member', () {
    test('S02 a live channel: name, viewers, the channel version', () {
      final member = Fc2LiveParse.member(Fixture.load('fc2live', 'S02-member-live').body, roomId: _channel);
      expect(member.detail.state, LiveState.live);
      expect(member.detail.card.anchorName, 'FC2USER475160OCC');
      expect(member.detail.card.title, 'FC2USER475160OCC', reason: 'no title: the name stands in');
      expect(member.detail.card.audience.online, 127);
      expect(member.detail.card.audience.cumulative, 9693);
      expect(member.version, isNotEmpty);
      expect(member.restricted, isFalse);
    });

    test('S02 a channel that never existed is NotFound; offline and paid are read', () {
      expect(
        () => Fc2LiveParse.member(Fixture.load('fc2live', 'S02-member-missing').body, roomId: '99999999'),
        throwsA(isA<NotFound>()),
      );
      final live = Fixture.load('fc2live', 'S02-member-live').body;
      final offline = Fc2LiveParse.member(live.replaceFirst('"is_publish": 1', '"is_publish": 0'), roomId: _channel);
      expect(offline.detail.state, LiveState.offline);
      expect(offline.detail.card.audience, Audience.none);
      final paid = Fc2LiveParse.member(live.replaceFirst('"fee": 0', '"fee": 1'), roomId: _channel);
      expect(paid.restricted, isTrue);
      expect(() => Fc2LiveParse.member(live, roomId: '1'), throwsA(isA<ApiChanged>()));
    });
  });

  group('§6 control', () {
    test('S03 the grant names the control socket of the channel', () {
      final grant = Fc2LiveParse.grant(Fixture.load('fc2live', 'S03-control').body, roomId: _channel);
      expect(grant.socket.path, '/control/channels/$_channel');
      expect(Fc2LiveParse.controlUrl(grant).queryParameters['control_token'], grant.controlToken);
      expect(
        () => Fc2LiveParse.grant('{"status":1,"url":"","control_token":"","orz_raw":""}', roomId: _channel),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('S04 the socket asks for HLS after connect_complete and holds the playlists', () async {
      final socket = _ReplaySocket(_serverMessages());
      final grant = Fc2LiveParse.grant(Fixture.load('fc2live', 'S03-control').body, roomId: _channel);
      Map<String, String>? headers;
      final control = await Fc2Control.open(
        grant,
        connect: (url, sent) async {
          headers = sent;
          return socket;
        },
      );
      expect(headers!['Cookie'], 'l_ortkn=${grant.orz}');
      expect(socket.sent, ['{"name":"get_hls_information","arguments":{},"id":1}']);
      expect(control.playlists.keys, containsAll([0, 10, 20, 30, 1, 11, 21, 31]));
      expect(control.playlists[31]!.path, '/a/stream/$_channel/31/playlist');
      expect(control.viewers, greaterThan(0));
      socket.drop();
      await control.done;
      expect(control.isOpen, isFalse);
    });

    test('S05 the master lists the modes that the qualities name', () {
      final master = Fixture.load('fc2live', 'S05-master').body;
      for (final quality in Fc2LiveParse.qualities) {
        expect(master, contains('/$_channel/${quality.id}/playlist?'));
      }
    });
  });

  group('adapter', () {
    test('streams: member → grant → held socket → high-latency lines; renewals reuse the socket', () async {
      final socket = _ReplaySocket(_serverMessages());
      final opened = <(Uri, Map<String, String>)>[];
      final site = _site(['S02-member-live', 'S03-control'], sockets: [socket], opened: opened);
      final detail = await site.detail(RoomRef('fc2live', _channel));
      final set = await site.streams(detail);
      expect(set.qualities.map((q) => q.id), ['30', '20', '10']);
      expect(set.lines.single.url.path, '/a/stream/$_channel/31/playlist');
      expect(set.lines.single.lease!.cutsConnection, isFalse);
      final low = await site.streams(detail, quality: Fc2LiveParse.qualities.last);
      expect(low.lines.single.url.path, '/a/stream/$_channel/11/playlist');
      expect(opened, hasLength(1));
      expect(opened.single.$1.queryParameters, contains('control_token'));
      await site.close();
      expect(socket.closed, isTrue);
    });

    test('a dropped socket is replaced on the next renewal', () async {
      final first = _ReplaySocket(_serverMessages());
      final second = _ReplaySocket(_serverMessages());
      final site = _site(['S02-member-live', 'S03-control'], sockets: [first, second]);
      final detail = await site.detail(RoomRef('fc2live', _channel));
      await site.streams(detail);
      first.drop();
      await Future<void>.delayed(Duration.zero);
      await site.streams(detail);
      expect(second.sent, hasLength(1));
      await site.close();
    });

    test('catalog: one category of site filters', () async {
      final site = _site(['S01-directory'], sockets: []);
      final categories = await site.categories();
      expect(categories.single.areas.map((a) => a.name), contains('雑談'));
      expect((await site.recommended()).items, hasLength(56));
      expect((await site.areaRooms(Fc2LiveParse.areas.first)).items, hasLength(21));
      expect(() => site.areaRooms(const Area(id: '7', name: 'x', categoryId: 'fc2live')), throwsA(isA<NotFound>()));
    });

    test('links', () async {
      final site = _site(const [], sockets: []);
      expect(await site.resolve('https://live.fc2.com/$_channel/'), RoomRef('fc2live', _channel));
      expect(await site.resolve('见 https://live.fc2.com/ja/$_channel/?from=x'), RoomRef('fc2live', _channel));
      expect(await site.resolve(_channel), RoomRef('fc2live', _channel));
      expect(await site.resolve('https://live.fc2.com/adult/'), isNull);
      expect(await site.resolve('https://www.douyu.com/9999'), isNull);
    });
  });
}
