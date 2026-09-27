import 'package:live_cast/src/failure.dart';
import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

/// A UPnP service of a device: its type and where to send actions.
@immutable
final class CastService {
  /// Creates a service.
  const new({required this.serviceType, required this.controlUrl});

  /// Service type (`urn:schemas-upnp-org:service:AVTransport:1`); SOAP
  /// actions are named after it.
  final String serviceType;

  /// Absolute control URL.
  final Uri controlUrl;

  @override
  bool operator ==(Object other) =>
      other is CastService && other.serviceType == serviceType && other.controlUrl == controlUrl;

  @override
  int get hashCode => Object.hash(serviceType, controlUrl);

  @override
  String toString() => 'CastService($serviceType at $controlUrl)';
}

/// A DLNA media renderer that can be cast to.
@immutable
final class CastDevice {
  /// Creates a device.
  const new({
    required this.id,
    required this.name,
    required this.location,
    required this.avTransport,
    this.renderingControl,
    this.manufacturer,
    this.modelName,
  });

  /// Unique device name (`uuid:…`), lower-cased.
  final String id;

  /// Name to show: the `friendlyName`, else the model, else the host.
  final String name;

  /// Where the description was read.
  final Uri location;

  /// The AVTransport service the cast is sent to.
  final CastService avTransport;

  /// The RenderingControl service (volume), when the device has one.
  final CastService? renderingControl;

  /// Manufacturer, if given.
  final String? manufacturer;

  /// Model name, if given.
  final String? modelName;

  /// The device's address on the network.
  String get host => location.host;

  @override
  bool operator ==(Object other) =>
      other is CastDevice &&
      other.id == id &&
      other.name == name &&
      other.location == location &&
      other.avTransport == avTransport &&
      other.renderingControl == renderingControl;

  @override
  int get hashCode => Object.hash(id, name, location, avTransport, renderingControl);

  @override
  String toString() => 'CastDevice($name, $id at $host)';
}

final RegExp _avTransport = RegExp(r'^urn:schemas-upnp-org:service:AVTransport:\d+$', caseSensitive: false);
final RegExp _renderingControl = RegExp(r'^urn:schemas-upnp-org:service:RenderingControl:\d+$', caseSensitive: false);

/// Reads a device description (UPnP Device Architecture 1.1 §2.3) fetched
/// from [location].
///
/// Returns the first device, root or embedded, with an AVTransport service
/// and a usable control URL; null when there is none (a media server, a
/// router). Relative URLs resolve against `URLBase`, else [location]. Element
/// names match by local name, so namespace prefixes and undeclared prefixes
/// do not matter. Throws [CastProtocolFailure] when the text is not a device
/// description.
CastDevice? parseDeviceDescription(String text, Uri location) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(_stripBom(text));
  } on XmlException catch (error) {
    throw CastProtocolFailure('description at ${location.host}: ${error.message}');
  }
  final root = document.rootElement;
  if (root.localName != 'root') throw CastProtocolFailure('description at ${location.host}: no <root>');
  final base = _baseOf(root, location);
  final devices = root.descendantElements.where((element) => element.localName == 'device').toList();
  if (devices.isEmpty) throw CastProtocolFailure('description at ${location.host}: no <device>');
  final rootDevice = devices.first;
  for (final device in devices) {
    final services = [
      for (final list in _children(device, 'serviceList'))
        for (final service in _children(list, 'service')) service,
    ];
    final avTransport = _service(services, _avTransport, base);
    if (avTransport == null) continue;
    final manufacturer = _text(device, 'manufacturer') ?? _text(rootDevice, 'manufacturer');
    final model = _text(device, 'modelName') ?? _text(rootDevice, 'modelName');
    final udn = _text(device, 'UDN') ?? _text(rootDevice, 'UDN');
    return CastDevice(
      id: (udn ?? 'location:$location').toLowerCase(),
      name: _text(device, 'friendlyName') ?? _text(rootDevice, 'friendlyName') ?? model ?? location.host,
      location: location,
      avTransport: avTransport,
      renderingControl: _service(services, _renderingControl, base),
      manufacturer: manufacturer,
      modelName: model,
    );
  }
  return null;
}

/// Resolves a URL from a description against [base].
///
/// Accepts absolute URLs, absolute paths and relative paths, including a
/// first segment with a colon that is not a scheme
/// (`_urn:schemas-upnp-org:service:AVTransport_control`, seen on libupnp
/// renderers), which `Uri.resolve` alone rejects. Null when it cannot be
/// resolved to an http(s) URL with a host.
Uri? resolveDescriptionUrl(Uri base, String reference) {
  final value = reference.trim();
  if (value.isEmpty) return null;
  final colon = value.indexOf(':');
  final slash = value.indexOf('/');
  // "x:" before any slash and not followed by "//" is a path segment, unless
  // x is http(s) itself.
  final segment = colon > 0 && (slash < 0 || colon < slash) && !value.startsWith('//', colon + 1);
  final scheme = segment ? value.substring(0, colon).toLowerCase() : null;
  final Uri resolved;
  try {
    if (scheme == null || scheme == 'http' || scheme == 'https') {
      resolved = base.resolve(value);
    } else {
      // Built by hand: resolving "./urn:…" would percent-encode the colon,
      // and embedded servers compare paths literally.
      final directory = base.path.substring(0, base.path.lastIndexOf('/') + 1);
      final query = value.indexOf('?');
      resolved = Uri(
        scheme: base.scheme,
        userInfo: base.userInfo,
        host: base.host,
        port: base.port,
        path: '${directory.isEmpty ? '/' : directory}${query < 0 ? value : value.substring(0, query)}',
        query: query < 0 ? null : value.substring(query + 1),
      );
    }
  } on FormatException {
    return null;
  }
  if (!(resolved.isScheme('http') || resolved.isScheme('https')) || resolved.host.isEmpty) return null;
  return resolved;
}

String _stripBom(String text) => text.startsWith('\uFEFF') ? text.substring(1) : text;

Uri _baseOf(XmlElement root, Uri location) {
  final declared = _text(root, 'URLBase');
  if (declared == null) return location;
  final base = Uri.tryParse(declared);
  if (base == null || !(base.isScheme('http') || base.isScheme('https')) || base.host.isEmpty) return location;
  return base;
}

CastService? _service(List<XmlElement> services, RegExp type, Uri base) {
  for (final service in services) {
    final serviceType = _text(service, 'serviceType');
    if (serviceType == null || !type.hasMatch(serviceType)) continue;
    final control = _text(service, 'controlURL');
    final url = control == null ? null : resolveDescriptionUrl(base, control);
    if (url != null) return CastService(serviceType: serviceType, controlUrl: url);
  }
  return null;
}

Iterable<XmlElement> _children(XmlElement parent, String localName) =>
    parent.childElements.where((element) => element.localName == localName);

/// The trimmed text of [parent]'s first child named [localName]; null when
/// missing or blank.
String? _text(XmlElement parent, String localName) {
  for (final child in _children(parent, localName)) {
    final text = child.innerText.trim();
    return text.isEmpty ? null : text;
  }
  return null;
}
