import 'package:live_cast/src/failure.dart';
import 'package:xml/xml.dart';

/// The SOAP request body of [action] on [serviceType], arguments in the
/// order given (UPnP Device Architecture 1.1 §3.2.1). Argument values are
/// escaped as XML text.
String soapEnvelope(String serviceType, String action, Map<String, String> arguments) {
  final body = StringBuffer();
  arguments.forEach((name, value) => body.write('<$name>${escapeXml(value)}</$name>'));
  return [
    '<?xml version="1.0" encoding="utf-8"?>',
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"',
    ' s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">',
    '<s:Body><u:$action xmlns:u="${escapeXml(serviceType)}">$body</u:$action></s:Body>',
    '</s:Envelope>',
  ].join();
}

/// The HTTP headers of a SOAP request, names in their canonical case.
Map<String, String> soapHeaders(String serviceType, String action) => {
  'Content-Type': 'text/xml; charset="utf-8"',
  'SOAPAction': '"$serviceType#$action"',
};

/// Reads the answer to [action]: its output arguments by name.
///
/// A SOAP fault with a UPnP error throws [UpnpActionFailure]; a fault
/// without one throws [CastProtocolFailure]; any other non-2xx status throws
/// [CastHttpFailure]. A 2xx answer with an empty or unexpected body counts as
/// success with no arguments: several renderers answer Play that way.
Map<String, String> parseSoapResponse(String action, int statusCode, String body) {
  XmlDocument? document;
  if (body.trim().isNotEmpty) {
    try {
      document = XmlDocument.parse(body.startsWith('\uFEFF') ? body.substring(1) : body);
    } on XmlException {
      document = null;
    }
  }
  final fault = document?.descendantElements.where((element) => element.localName == 'Fault').firstOrNull;
  if (fault != null) {
    final error = fault.descendantElements.where((element) => element.localName == 'UPnPError').firstOrNull;
    final code = int.tryParse(_text(error, 'errorCode') ?? '');
    if (code != null) throw UpnpActionFailure(action, code, _text(error, 'errorDescription'));
    throw CastProtocolFailure('$action: SOAP fault ${_text(fault, 'faultstring') ?? ''} (HTTP $statusCode)'.trim());
  }
  if (statusCode < 200 || statusCode >= 300) throw CastHttpFailure(statusCode, action);
  final response = document?.descendantElements.where((element) => element.localName == '${action}Response');
  return {
    for (final argument in response?.firstOrNull?.childElements ?? const <XmlElement>[])
      argument.localName: argument.innerText,
  };
}

/// [text] escaped for XML text and attribute values. Characters XML 1.0 does
/// not allow (control characters other than tab and line breaks) are dropped.
String escapeXml(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    switch (rune) {
      case 0x26:
        out.write('&amp;');
      case 0x3C:
        out.write('&lt;');
      case 0x3E:
        out.write('&gt;');
      case 0x22:
        out.write('&quot;');
      case 0x27:
        out.write('&apos;');
      case 0x09 || 0x0A || 0x0D:
        out.writeCharCode(rune);
      case < 0x20 || 0xFFFE || 0xFFFF:
        break;
      default:
        out.writeCharCode(rune);
    }
  }
  return out.toString();
}

String? _text(XmlElement? parent, String localName) {
  if (parent == null) return null;
  for (final element in parent.descendantElements) {
    if (element.localName == localName) {
      final text = element.innerText.trim();
      return text.isEmpty ? null : text;
    }
  }
  return null;
}
