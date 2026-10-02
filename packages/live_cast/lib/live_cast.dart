/// DLNA casting of Pure Live (docs/N-多画面和投屏/N02-投屏/N02.1-投屏/record.md): SSDP search for
/// media renderers, device descriptions, AVTransport control over SOAP and
/// the cast dialog's logic. Pure Dart on `dart:io`; sockets and HTTP are
/// injectable so tests never touch the network.
library;

export 'src/controller.dart';
export 'src/description.dart';
export 'src/discovery.dart';
export 'src/failure.dart';
export 'src/http.dart';
export 'src/renderer.dart';
export 'src/soap.dart' show escapeXml, parseSoapResponse, soapEnvelope, soapHeaders;
export 'src/ssdp.dart';
