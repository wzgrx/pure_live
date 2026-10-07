import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// How many bytes of a line are read: enough for a container header, a
/// playlist or the first FLV tags, never the stream itself.
const int mediaHeadLimit = 64 * 1024;

/// What the first bytes of a line are.
enum MediaContainer {
  /// `FLV` header.
  flv('FLV'),

  /// `#EXTM3U` playlist.
  hlsPlaylist('HLS 播放列表'),

  /// MPEG-TS (sync byte 0x47).
  mpegTs('MPEG-TS'),

  /// Fragmented MP4 (`ftyp` or `styp` box).
  fmp4('fMP4'),

  /// A DASH manifest (`<MPD`).
  dash('DASH 清单'),

  /// An HTML page (an error or login page).
  html('HTML 页面'),

  /// Nothing was read.
  empty('空'),

  /// Something else.
  unknown('无法识别');

  new(this.label);

  /// Chinese name for the report.
  final String label;
}

/// The container of [bytes] (the archived probe's `_container`, plus HTML,
/// DASH and an empty answer).
MediaContainer container(List<int> bytes) {
  if (bytes.isEmpty) return MediaContainer.empty;
  if (bytes.length >= 3 && bytes[0] == 0x46 && bytes[1] == 0x4C && bytes[2] == 0x56) return MediaContainer.flv;
  if (bytes[0] == 0x47 && (bytes.length < 189 || bytes[188] == 0x47)) return MediaContainer.mpegTs;
  if (bytes.length >= 8) {
    final box = String.fromCharCodes(bytes.sublist(4, 8));
    if (box == 'ftyp' || box == 'styp') return MediaContainer.fmp4;
  }
  final text = utf8.decode(bytes.take(512).toList(), allowMalformed: true).replaceFirst('﻿', '').trimLeft();
  if (text.startsWith('#EXTM3U')) return MediaContainer.hlsPlaylist;
  final lower = text.toLowerCase();
  if (lower.startsWith('<?xml') && lower.contains('<mpd') || lower.startsWith('<mpd')) return MediaContainer.dash;
  if (lower.startsWith('<!doctype html') || lower.startsWith('<html') || lower.contains('<body')) {
    return MediaContainer.html;
  }
  return MediaContainer.unknown;
}

/// Whether [found] is what a line of [format] at [url] should start with.
/// HLS lines must be a playlist; FLV lines an FLV header; a line of format
/// `other` or of no declared format any media container (the path's `.flv`
/// or `.m3u8` decides when there is one).
bool containerMatches(StreamFormat? format, Uri url, MediaContainer found) {
  final path = url.path.toLowerCase();
  final expected =
      format ??
      (path.endsWith('.m3u8')
          ? StreamFormat.hls
          : path.endsWith('.flv')
          ? StreamFormat.flv
          : StreamFormat.other);
  return switch (expected) {
    StreamFormat.flv => found == MediaContainer.flv,
    StreamFormat.hls => found == MediaContainer.hlsPlaylist,
    StreamFormat.other => const {
      MediaContainer.flv,
      MediaContainer.hlsPlaylist,
      MediaContainer.mpegTs,
      MediaContainer.fmp4,
      MediaContainer.dash,
    }.contains(found),
  };
}

/// The first bytes of a line.
@immutable
final class MediaHead {
  /// Creates the head.
  new({required this.status, required List<int> bytes, this.error}) : bytes = List.unmodifiable(bytes);

  /// HTTP status; 0 when no response arrived.
  final int status;

  /// At most [mediaHeadLimit] bytes.
  final List<int> bytes;

  /// Why nothing was read (transport failure), or null.
  final String? error;

  /// Whether the status is 2xx.
  bool get ok => status >= 200 && status < 300;
}

/// Reads the first [limit] bytes of [url] through [http] with the line's
/// [headers] and drops the connection: live media never ends, so the body
/// is streamed and cancelled (the archived probe's `_head`).
Future<MediaHead> head(
  LiveHttp http,
  String site,
  Uri url,
  Map<String, String> headers, {
  int limit = mediaHeadLimit,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final cancel = CancelToken();
  try {
    final response = await http.open(
      LiveRequest(site: site, url: url, headers: headers, timeout: timeout, cancel: cancel),
    );
    final bytes = <int>[];
    if (response.status >= 200 && response.status < 300) {
      try {
        await for (final chunk in response.body) {
          bytes.addAll(chunk);
          if (bytes.length >= limit) break;
        }
      } on TransportFailure catch (failure) {
        if (bytes.isEmpty) return MediaHead(status: response.status, bytes: const [], error: failure.reason.name);
      }
    } else {
      await response.discard();
    }
    return MediaHead(status: response.status, bytes: bytes.length > limit ? bytes.sublist(0, limit) : bytes);
  } on TransportFailure catch (failure) {
    return MediaHead(status: 0, bytes: const [], error: 'TransportFailure ${failure.reason.name}');
  } finally {
    cancel.cancel();
  }
}
