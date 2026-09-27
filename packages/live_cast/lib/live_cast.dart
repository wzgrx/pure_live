/// DLNA casting for Pure Live v4 (F-CAST-01, docs/adr/0027-dlna-cast.md): SSDP
/// search for media renderers, device descriptions and AVTransport control
/// over SOAP. Pure Dart on `dart:io`; sockets and HTTP are injectable so
/// tests never touch the network.
library;

export 'src/description.dart';
export 'src/discovery.dart';
export 'src/failure.dart';
export 'src/http.dart';
export 'src/renderer.dart';
export 'src/soap.dart' show escapeXml, parseSoapResponse, soapEnvelope, soapHeaders;
export 'src/ssdp.dart';
