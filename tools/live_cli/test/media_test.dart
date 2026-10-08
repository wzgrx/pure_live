import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_cli/live_cli.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  group('container', () {
    test('tells FLV, playlists, MPEG-TS and fMP4 apart', () {
      expect(container(flvBytes), MediaContainer.flv);
      expect(container(m3u8Bytes), MediaContainer.hlsPlaylist);
      expect(container(utf8.encode('﻿\n#EXTM3U\n')), MediaContainer.hlsPlaylist);
      expect(container([0x47, ...List.filled(187, 0), 0x47, 0]), MediaContainer.mpegTs);
      expect(container([0, 0, 0, 0x20, ...'ftypisom'.codeUnits]), MediaContainer.fmp4);
      expect(container(utf8.encode('<?xml version="1.0"?><MPD>')), MediaContainer.dash);
    });

    test('an empty answer, an HTML error page and noise are not media', () {
      expect(container(const []), MediaContainer.empty);
      expect(container(utf8.encode('<!DOCTYPE html><html><body>403')), MediaContainer.html);
      expect(container(utf8.encode('{"code":-352}')), MediaContainer.unknown);
      expect(container([0x47, ...List.filled(187, 0), 0x00]), MediaContainer.unknown);
    });

    test('a line must start with what its format says', () {
      final flv = Uri.parse('https://cdn.example/live/a.flv');
      final m3u8 = Uri.parse('https://cdn.example/live/a.m3u8');
      expect(containerMatches(StreamFormat.flv, flv, MediaContainer.flv), isTrue);
      expect(containerMatches(StreamFormat.hls, m3u8, MediaContainer.flv), isFalse);
      expect(containerMatches(null, m3u8, MediaContainer.hlsPlaylist), isTrue);
      expect(containerMatches(StreamFormat.other, flv, MediaContainer.mpegTs), isTrue);
      expect(containerMatches(StreamFormat.other, flv, MediaContainer.html), isFalse);
    });
  });

  group('head', () {
    late ServerSocket server;
    late Completer<void> hungUp;

    // A raw loopback server: answers 128 KiB of MPEG-TS and keeps the
    // connection open, so only the client can end it; `/missing` is a 404.
    setUp(() async {
      hungUp = Completer<void>();
      server = (await ServerSocket.bind(InternetAddress.loopbackIPv4, 0))
        ..listen((socket) {
          // A write after the client's reset fails here, not in the test.
          unawaited(
            socket.done.then<void>(
              (_) {},
              onError: (Object _) {
                if (!hungUp.isCompleted) hungUp.complete();
              },
            ),
          );
          final request = StringBuffer();
          var answered = false;
          socket.listen(
            (data) {
              request.write(String.fromCharCodes(data));
              if (answered || !request.toString().contains('\r\n\r\n')) return;
              answered = true;
              if (request.toString().startsWith('GET /missing')) {
                socket.write('HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n');
                return;
              }
              socket
                ..write('HTTP/1.1 200 OK\r\nContent-Type: video/mp2t\r\n\r\n')
                ..add(List<int>.filled(128 * 1024, 0x47));
            },
            onDone: () {
              if (!hungUp.isCompleted) hungUp.complete();
              socket.destroy();
            },
            onError: (Object _) {
              if (!hungUp.isCompleted) hungUp.complete();
            },
          );
        });
    });

    tearDown(() => server.close());

    test('reads 64 KiB and drops the connection', () async {
      final http = IoLiveHttp();
      addTearDown(http.close);
      final answer = await head(http, 'bilibili', Uri.parse('http://127.0.0.1:${server.port}/live.ts'), const {
        'referer': 'https://live.bilibili.com/',
      });
      expect(answer.status, 200);
      expect(answer.bytes, hasLength(mediaHeadLimit));
      expect(container(answer.bytes), MediaContainer.mpegTs);
      // The server never ends the answer: the client must have hung up.
      await hungUp.future.timeout(const Duration(seconds: 5));
    });

    test('a refused line reads nothing and keeps the status', () async {
      final http = IoLiveHttp();
      addTearDown(http.close);
      final answer = await head(http, 'bilibili', Uri.parse('http://127.0.0.1:${server.port}/missing'), const {});
      expect(answer.status, 404);
      expect(answer.ok, isFalse);
      expect(answer.bytes, isEmpty);
    });
  });
}
