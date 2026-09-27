import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/twitch/twitch_site.dart';

void main() {
  group('Twitch directory connection parser', () {
    test('keeps usable edges when pageInfo is omitted', () {
      final result = TwitchSite.parseConnection({
        'edges': [
          {
            'cursor': 'cursor-1',
            'node': {'id': 'stream-1'},
          },
        ],
      });

      expect(result.edges, hasLength(1));
      expect(result.edges.single['cursor'], 'cursor-1');
      expect(result.hasNextPage, isFalse);
    });

    test('honours a boolean hasNextPage value', () {
      final result = TwitchSite.parseConnection({
        'edges': const <dynamic>[],
        'pageInfo': {'hasNextPage': true},
      });

      expect(result.edges, isEmpty);
      expect(result.hasNextPage, isTrue);
    });

    test('ignores malformed edge entries instead of crashing the page', () {
      final result = TwitchSite.parseConnection({
        'edges': [
          null,
          'invalid',
          {'cursor': 'cursor-2'},
        ],
        'pageInfo': null,
      });

      expect(result.edges, [
        {'cursor': 'cursor-2'},
      ]);
      expect(result.hasNextPage, isFalse);
    });

    test('treats a missing connection as an empty terminal page', () {
      final result = TwitchSite.parseConnection(null);

      expect(result.edges, isEmpty);
      expect(result.hasNextPage, isFalse);
    });
  });

  group('Twitch request identity and integrity response', () {
    test('generates the 32-character hexadecimal device id used by web requests', () {
      final value = TwitchSite.generateDeviceId(Random(7));

      expect(value, hasLength(32));
      expect(value, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(TwitchSite.generateDeviceId(Random(7)), value);
    });

    test('detects integrity errors in object and batched GraphQL envelopes', () {
      expect(
        TwitchSite.hasIntegrityError({
          'errors': [
            {'message': 'failed integrity check'},
          ],
        }),
        isTrue,
      );
      expect(
        TwitchSite.hasIntegrityError([
          {
            'data': null,
            'errors': [
              {'message': 'Integrity token expired'},
            ],
          },
        ]),
        isTrue,
      );
      expect(
        TwitchSite.hasIntegrityError([
          {
            'data': {'game': null},
            'errors': [
              {'message': 'unknown game'},
            ],
          },
        ]),
        isFalse,
      );
    });

    test('extracts an auth token from a complete Twitch cookie without truncating equals signs', () {
      expect(TwitchSite.extractAuthToken('persistent=123; auth-token=abc==; unique_id=value'), 'abc==');
      expect(TwitchSite.extractAuthToken('persistent=123'), isNull);
      expect(TwitchSite.extractAuthToken('auth-token=; persistent=123'), isNull);
    });

    test('uses the endpoint-specific device id header when minting integrity tokens', () {
      final headers = TwitchSite.buildIntegrityHeaders({
        'Client-ID': 'client-id-fixture',
        'Device-Id': 'graph-device',
        'Client-Integrity': 'expired-token',
      }, 'integrity-device');

      expect(headers['Client-ID'], 'client-id-fixture');
      expect(headers['X-Device-Id'], 'integrity-device');
      expect(headers, isNot(contains('Device-Id')));
      expect(headers, isNot(contains('Client-Integrity')));
    });

    test('normalizes Twitch integrity expirations expressed in seconds or milliseconds', () {
      expect(TwitchSite.normalizeIntegrityExpirationMilliseconds(1800000000), 1800000000000);
      expect(TwitchSite.normalizeIntegrityExpirationMilliseconds('1800000000'), 1800000000000);
      expect(TwitchSite.normalizeIntegrityExpirationMilliseconds(1800000000000), 1800000000000);
      expect(TwitchSite.normalizeIntegrityExpirationMilliseconds(0), isNull);
      expect(TwitchSite.normalizeIntegrityExpirationMilliseconds('invalid'), isNull);
    });
  });
}
