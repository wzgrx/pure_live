import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live_app/features/search/web_search_links.dart';

import '../fakes.dart';

/// An adapter without native search (third-batch shape).
final class _NoSearch implements LiveSite {
  @override
  String get id => 'picarto';

  @override
  String get name => 'Picarto';
}

void main() {
  test('F-SRC-02: the platform search page carries the encoded keyword', () {
    expect(
      webSearchUrl('picarto', ' 猫 cat&x '),
      Uri.parse('https://picarto.tv/search?q=${Uri.encodeComponent('猫 cat&x')}'),
    );
    expect(webSearchUrl('douyin', 'a/b').toString(), 'https://www.douyin.com/search/a%2Fb?type=live');
    expect(webSearchUrl('picarto', '  '), isNull);
    expect(webSearchUrl('unknown', 'x'), isNull);
  });

  test('F-SRC-02: only adapters without SearchSource and with a known page need the web', () {
    expect(needsWebSearch('picarto', _NoSearch()), isTrue);
    expect(needsWebSearch('douyu', FakeSite('douyu')), isFalse, reason: 'native search');
    expect(needsWebSearch('kick', _NoSearch()), isFalse, reason: 'no known search page');
  });

  group('F-SRC-02 links on the page', () {
    final base = Uri.parse('https://picarto.tv/search?q=cat');
    final links = [
      'https://picarto.tv/Alice',
      'https://picarto.tv/Alice#chat',
      '/Bob',
      'javascript:void(0)',
      'bilibili://live/1',
      'https://picarto.tv/search?q=cat',
      'https://user:pw@evil.test/',
      42,
      'https://picarto.tv/Carol',
    ];

    test('Windows hands back the script string: decoded once', () {
      expect(pageLinks(jsonEncode(links), base: base), [
        Uri.parse('https://picarto.tv/Alice'),
        Uri.parse('https://picarto.tv/Bob'),
        Uri.parse('https://picarto.tv/Carol'),
      ]);
    });

    test('Android quotes it once more: decoded twice', () {
      expect(pageLinks(jsonEncode(jsonEncode(links)), base: base), hasLength(3));
    });

    test('a list, a limit, and junk results', () {
      expect(pageLinks(links, base: base, limit: 2), hasLength(2));
      expect(pageLinks(null), isEmpty);
      expect(pageLinks('not json'), isEmpty);
      expect(pageLinks('{"a":1}'), isEmpty);
    });
  });

  group('F-SRC-02 rooms from links', () {
    Future<RoomRef?> resolver(String input) async {
      if (input.contains('fail')) throw const NetworkFailure('picarto', 'offline');
      final name = Uri.parse(input).pathSegments.firstOrNull;
      return name == null || name == 'search' ? null : RoomRef('picarto', name.toLowerCase());
    }

    test('rooms in link order, one per room; failures and non-rooms skipped', () async {
      final found = await findRooms([
        Uri.parse('https://picarto.tv/Alice'),
        Uri.parse('https://picarto.tv/search'),
        Uri.parse('https://picarto.tv/fail'),
        Uri.parse('https://picarto.tv/alice?ref=1'),
        Uri.parse('https://picarto.tv/Bob'),
      ], resolver);
      expect([for (final entry in found) entry.room.roomId], ['alice', 'bob']);
      expect(found.first.link, Uri.parse('https://picarto.tv/Alice'));
    });

    test('at most [concurrency] resolutions run at once', () async {
      var running = 0;
      var peak = 0;
      final gates = <Completer<void>>[];
      Future<RoomRef?> slow(String input) async {
        running++;
        peak = running > peak ? running : peak;
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
        running--;
        return RoomRef('picarto', input.split('/').last);
      }

      final links = [for (var i = 0; i < 10; i++) Uri.parse('https://picarto.tv/r$i')];
      final future = findRooms(links, slow, concurrency: 3);
      while (gates.length < links.length) {
        await Future<void>.delayed(Duration.zero);
        for (final gate in gates) {
          if (!gate.isCompleted) gate.complete();
        }
      }
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
      expect(await future, hasLength(10));
      expect(peak, 3);
    });
  });
}
