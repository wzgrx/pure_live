import 'dart:async';

import 'package:live_cast/src/description.dart';
import 'package:live_cast/src/failure.dart';
import 'package:live_cast/src/http.dart';
import 'package:live_cast/src/soap.dart';
import 'package:meta/meta.dart';

/// What to cast.
@immutable
final class CastMedia {
  /// Creates media. An empty [title] puts the URL there, and a null
  /// [mimeType] declares any type (`http-get:*:*:*`), both as 3.x did.
  const new({required this.url, this.title = '', this.mimeType});

  /// Stream URL the renderer opens itself.
  final String url;

  /// Title shown on the renderer.
  final String title;

  /// MIME type for the metadata; null for any.
  final String? mimeType;

  /// DLNA protocol info of the resource: `http-get:*:<mime>:*`.
  String get protocolInfo => 'http-get:*:${mimeType ?? '*'}:*';

  @override
  bool operator ==(Object other) =>
      other is CastMedia && other.url == url && other.title == title && other.mimeType == mimeType;

  @override
  int get hashCode => Object.hash(url, title, mimeType);

  @override
  String toString() => 'CastMedia(${mimeType ?? '*'}, ${title.isEmpty ? url : title})';

  /// The title of a live room on the receiver: `主播 - 标题`, the title alone
  /// without a streamer, the streamer alone without a title, empty without
  /// both (the URL then; 3.x always showed the URL).
  static String roomTitle({required String anchor, required String title}) =>
      [anchor.trim(), title.trim()].where((part) => part.isNotEmpty).join(' - ');
}

/// DIDL-Lite metadata for [media]: the item 3.x sent (`dlna_dart` 0.1.1
/// `XmlText.setPlayURLXml`) without its placeholder artist (`unknow`) and its
/// date, which was not a valid `dc:date`. Some renderers (Xiaomi, several TV
/// boxes) refuse or show nothing without metadata.
String didlLite(CastMedia media) {
  final title = media.title.trim().isEmpty ? media.url : media.title.trim();
  return [
    '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"',
    ' xmlns:dc="http://purl.org/dc/elements/1.1/"',
    ' xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"',
    ' xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/">',
    '<item id="id" parentID="0" restricted="0">',
    '<dc:title>${escapeXml(title)}</dc:title>',
    '<upnp:class>object.item.videoItem</upnp:class>',
    '<res protocolInfo="${escapeXml(media.protocolInfo)}">${escapeXml(media.url)}</res>',
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

/// A receiver in the cast list (3.x `DlnaCastDevice` in
/// `modules/live_play/dialogs/live_dlna_dialog.dart`). The page and
/// `DlnaCastController` talk to this interface; tests fake it.
abstract interface class DlnaCastDevice {
  /// Stable id: the renderer's UDN (`uuid:…`), lower-cased.
  String get id;

  /// Name to show; may be empty (the page shows "unknown device").
  String get name;

  /// The base address 3.x showed under the name.
  String get address;

  /// Loads [source] without starting it (SetAVTransportURI).
  Future<void> setSource(String source);

  /// Plays at normal speed.
  Future<void> play();

  /// Pauses; sent to the previous receiver when the cast moves.
  Future<void> pause();

  /// Stops.
  Future<void> stop();

  /// Reads the transport state (GetTransportInfo).
  Future<TransportInfo> transportInfo();
}

/// A receiver that takes the metadata with the source: the title to show
/// and the type ([CastMedia]). `DlnaCastController` uses it when it has a
/// title; receivers without it get [DlnaCastDevice.setSource].
abstract interface class CastMediaTarget {
  /// Loads [media] without starting it (SetAVTransportURI).
  Future<void> setMedia(CastMedia media);
}

/// [DlnaCastDevice] over SOAP to the renderer's AVTransport service
/// (instance 0). Usable after the search that found it has stopped.
final class DlnaRenderer implements DlnaCastDevice, CastMediaTarget {
  /// Creates a renderer client for [device].
  new(
    this.device, {
    required this._http,
    this.timeout = const Duration(seconds: 15),
    this.settle = const Duration(milliseconds: 800),
  });

  /// The renderer.
  final CastDevice device;

  final CastHttp _http;

  /// Limit for one action, connecting included (3.x waited 15 seconds for
  /// the answer).
  final Duration timeout;

  /// Wait before Play is asked again when the renderer is still loading.
  final Duration settle;

  @override
  String get id => device.id;

  @override
  String get name => device.name;

  @override
  String get address => device.address;

  @override
  Future<void> setSource(String source) => setMedia(CastMedia(url: source));

  /// SetAVTransportURI with [media].
  ///
  /// A renderer busy with another stream (701, 705, 715) is stopped and asked
  /// once more; every other failure is thrown as it came.
  @override
  Future<void> setMedia(CastMedia media) async {
    final arguments = {'InstanceID': '0', 'CurrentURI': media.url, 'CurrentURIMetaData': didlLite(media)};
    try {
      await _invoke('SetAVTransportURI', arguments);
    } on UpnpActionFailure catch (failure) {
      if (!failure.error.busy) rethrow;
      try {
        await stop();
      } on CastFailure {
        // The retry below reports what matters.
      }
      await _invoke('SetAVTransportURI', arguments);
    }
  }

  /// Play at normal speed. A Play refused with 701 while the renderer is
  /// still loading the source is asked once more after [settle].
  @override
  Future<void> play() async {
    try {
      await _invoke('Play', {'InstanceID': '0', 'Speed': '1'});
    } on UpnpActionFailure catch (failure) {
      if (failure.error != UpnpError.transitionNotAvailable) rethrow;
      await Future<void>.delayed(settle);
      await _invoke('Play', {'InstanceID': '0', 'Speed': '1'});
    }
  }

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

  @override
  String toString() => 'DlnaRenderer($device)';
}
