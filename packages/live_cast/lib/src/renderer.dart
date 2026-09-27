import 'dart:async';

import 'package:live_cast/src/description.dart';
import 'package:live_cast/src/failure.dart';
import 'package:live_cast/src/http.dart';
import 'package:live_cast/src/soap.dart';
import 'package:meta/meta.dart';

/// MIME types a cast declares in its metadata.
abstract final class CastMime {
  /// HTTP-FLV.
  static const flv = 'video/x-flv';

  /// HLS playlist.
  static const hls = 'application/vnd.apple.mpegurl';

  /// MPEG transport stream.
  static const mpegTs = 'video/mp2t';

  /// MP4.
  static const mp4 = 'video/mp4';

  /// The type the path of [url] suggests (`.m3u8`, `.flv`, `.ts`, `.mp4`),
  /// else [fallback].
  static String guess(Uri url, {String fallback = flv}) {
    final path = url.path.toLowerCase();
    if (path.endsWith('.m3u8') || path.endsWith('.m3u')) return hls;
    if (path.endsWith('.flv')) return flv;
    if (path.endsWith('.ts')) return mpegTs;
    if (path.endsWith('.mp4')) return mp4;
    return fallback;
  }
}

/// What to cast.
@immutable
final class CastMedia {
  /// Creates media.
  const new({required this.url, required this.title, this.mimeType = CastMime.flv});

  /// Stream URL the renderer opens itself.
  final Uri url;

  /// Title shown on the renderer.
  final String title;

  /// MIME type for the metadata.
  final String mimeType;

  /// DLNA protocol info of the resource: `http-get:*:<mime>:*`.
  String get protocolInfo => 'http-get:*:$mimeType:*';

  @override
  bool operator ==(Object other) =>
      other is CastMedia && other.url == url && other.title == title && other.mimeType == mimeType;

  @override
  int get hashCode => Object.hash(url, title, mimeType);

  @override
  String toString() => 'CastMedia($mimeType, $title)';
}

/// Longest title put into the metadata; some renderers reject long metadata
/// with 605.
const int maxCastTitleLength = 80;

/// Minimal DIDL-Lite metadata for [media]: title, `object.item.videoItem` and
/// one resource with its protocol info. Some renderers (Xiaomi, several TV
/// boxes) refuse or show nothing without it.
String didlLite(CastMedia media) {
  final runes = media.title.trim().runes;
  final title = runes.length > maxCastTitleLength
      ? '${String.fromCharCodes(runes.take(maxCastTitleLength - 1))}…'
      : String.fromCharCodes(runes);
  return [
    '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"',
    ' xmlns:dc="http://purl.org/dc/elements/1.1/"',
    ' xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">',
    '<item id="0" parentID="-1" restricted="1">',
    '<dc:title>${escapeXml(title)}</dc:title>',
    '<upnp:class>object.item.videoItem</upnp:class>',
    '<res protocolInfo="${escapeXml(media.protocolInfo)}">${escapeXml(media.url.toString())}</res>',
    '</item>',
    '</DIDL-Lite>',
  ].join();
}

/// `CurrentTransportState` of AVTransport.
enum TransportState {
  /// `STOPPED`.
  stopped('STOPPED'),

  /// `PLAYING`.
  playing('PLAYING'),

  /// `TRANSITIONING`: loading.
  transitioning('TRANSITIONING'),

  /// `PAUSED_PLAYBACK`.
  pausedPlayback('PAUSED_PLAYBACK'),

  /// `PAUSED_RECORDING`.
  pausedRecording('PAUSED_RECORDING'),

  /// `RECORDING`.
  recording('RECORDING'),

  /// `NO_MEDIA_PRESENT`.
  noMediaPresent('NO_MEDIA_PRESENT'),

  /// Anything else.
  unknown('');

  new(this.value);

  /// The value on the wire.
  final String value;

  /// The state named [value], or [unknown].
  static TransportState parse(String? value) {
    final wanted = value?.trim().toUpperCase();
    for (final state in values) {
      if (state.value == wanted && state != unknown) return state;
    }
    return unknown;
  }
}

/// The answer to GetTransportInfo.
@immutable
final class TransportInfo {
  /// Creates the info.
  const new({required this.state, this.status, this.speed});

  /// Transport state.
  final TransportState state;

  /// `CurrentTransportStatus`: `OK` or `ERROR_OCCURRED`.
  final String? status;

  /// `CurrentSpeed`, usually `1`.
  final String? speed;

  /// Whether the renderer reports an error.
  bool get failed => status?.trim().toUpperCase() == 'ERROR_OCCURRED';

  @override
  bool operator ==(Object other) =>
      other is TransportInfo && other.state == state && other.status == status && other.speed == speed;

  @override
  int get hashCode => Object.hash(state, status, speed);

  @override
  String toString() => 'TransportInfo(${state.name}${status == null ? '' : ', $status'})';
}

/// Commands to one renderer. The app talks to this interface; tests fake it.
abstract interface class CastRenderer {
  /// The renderer.
  CastDevice get device;

  /// SetAVTransportURI: loads [media] without starting it.
  Future<void> setMedia(CastMedia media);

  /// Play at normal speed.
  Future<void> play();

  /// Pause.
  Future<void> pause();

  /// Stop.
  Future<void> stop();

  /// GetTransportInfo.
  Future<TransportInfo> transportInfo();
}

/// [CastRenderer] over SOAP to the device's AVTransport service (instance 0).
final class DlnaRenderer implements CastRenderer {
  /// Creates a renderer client for [device].
  new(this.device, {required this._http, this.timeout = const Duration(seconds: 6)});

  @override
  final CastDevice device;

  final CastHttp _http;

  /// Limit for one action.
  final Duration timeout;

  @override
  Future<void> setMedia(CastMedia media) => _invoke('SetAVTransportURI', {
    'InstanceID': '0',
    'CurrentURI': media.url.toString(),
    'CurrentURIMetaData': didlLite(media),
  });

  @override
  Future<void> play() => _invoke('Play', {'InstanceID': '0', 'Speed': '1'});

  @override
  Future<void> pause() => _invoke('Pause', {'InstanceID': '0'});

  @override
  Future<void> stop() => _invoke('Stop', {'InstanceID': '0'});

  @override
  Future<TransportInfo> transportInfo() async {
    final values = await _invoke('GetTransportInfo', {'InstanceID': '0'});
    return TransportInfo(
      state: TransportState.parse(values['CurrentTransportState']),
      status: values['CurrentTransportStatus'],
      speed: values['CurrentSpeed'],
    );
  }

  Future<Map<String, String>> _invoke(String action, Map<String, String> arguments) async {
    final service = device.avTransport;
    final response = await _http.send(
      'POST',
      service.controlUrl,
      timeout: timeout,
      headers: soapHeaders(service.serviceType, action),
      body: soapEnvelope(service.serviceType, action, arguments),
    );
    return parseSoapResponse(action, response.statusCode, response.body);
  }
}

/// Casts [media] to [renderer]: sets the source, then plays (REG-ROOM-016:
/// one command sequence, the source before play).
///
/// A renderer busy with another stream (701, 705, 715 on SetAVTransportURI)
/// is stopped and asked once more. A Play refused with 701 while the
/// renderer is still loading is retried once after [settle]. Every other
/// failure is thrown as it came.
Future<void> castTo(
  CastRenderer renderer,
  CastMedia media, {
  Duration settle = const Duration(milliseconds: 800),
}) async {
  try {
    await renderer.setMedia(media);
  } on UpnpActionFailure catch (failure) {
    if (!failure.error.busy) rethrow;
    try {
      await renderer.stop();
    } on CastFailure {
      // The retry below reports what matters.
    }
    await renderer.setMedia(media);
  }
  try {
    await renderer.play();
  } on UpnpActionFailure catch (failure) {
    if (failure.error != UpnpError.transitionNotAvailable) rethrow;
    await Future<void>.delayed(settle);
    await renderer.play();
  }
}
