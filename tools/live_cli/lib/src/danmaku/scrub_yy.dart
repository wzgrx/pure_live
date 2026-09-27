import 'dart:convert';
import 'dart:typed_data';

import 'package:live_cli/src/danmaku/frame_scrub.dart';
import 'package:live_cli/src/danmaku/recorder.dart';
import 'package:live_danmaku/live_danmaku.dart';

/// YY (spec/sites/yy.md §11): the anonymous session (uid, user name,
/// password, cookie) and the connection UUID are replaced wherever they
/// appear, the client packets that carry them are rebuilt from the
/// replacements; chat senders get pseudonyms and lose the extra items;
/// packets that are not decoded keep their header and lose their payload.
class YyFrameScrubber extends FrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  static const _anonymousLoginReply = 778500;
  static const _apLogin = 775684;
  static const _router = 513035;
  static const _routerReply = 512011;
  static const _subscribeApps = 538456;
  static const _joinGroups = 537944;
  static const _groupMessage = 533080;
  static const _bySidMessage = 28760;
  static const _joinChannelReply = 2048514;
  static const _kept = {778244, 775940, 794116, 794372};

  var _uid = 0;
  var _username = '';
  var _password = '';
  List<int> _cookie = const [];
  var _uuid = '';

  int get _topSid => int.tryParse(detail.danmakuKeys['sid'] ?? detail.ref.roomId) ?? 0;

  int get _subSid => int.tryParse(detail.danmakuKeys['ssid'] ?? '') ?? _topSid;

  @override
  Uri scrubUrl(Uri url) {
    final uuid = url.queryParameters['uuid'];
    if (uuid == null) return url;
    _uuid = names.secret(uuid);
    record('url.uuid', 'secret');
    return url.replace(queryParameters: {...url.queryParameters, 'uuid': _uuid});
  }

  int _digits(int value) => value == 0 ? 0 : int.parse(names.digits('$value'));

  /// Binary secrets (cookie, ticket): the same length, derived from the
  /// shape-keeping replacement of their hex form.
  List<int> _bytes(List<int> original) {
    if (original.isEmpty) return original;
    final shaped = names.secret([for (final byte in original) byte.toRadixString(16).padLeft(2, '0')].join());
    int nibble(int unit) => unit <= 0x39 ? unit - 0x30 : (unit - 0x61) % 16;
    return [
      for (var i = 0; i + 1 < shaped.length; i += 2)
        (nibble(shaped.codeUnitAt(i)) << 4) | nibble(shaped.codeUnitAt(i + 1)),
    ];
  }

  @override
  List<int>? scrubFrame(CapturedFrame frame) {
    final bytes = Uint8List.fromList(frame.bytes);
    final out = BytesBuilder();
    var offset = 0;
    while (bytes.length - offset >= 10) {
      final length = ByteData.sublistView(bytes, offset).getUint32(0, Endian.little);
      if (length < 10 || offset + length > bytes.length) break;
      out.add(_packet(Uint8List.sublistView(bytes, offset, offset + length)));
      offset += length;
    }
    if (offset < bytes.length) record('frame.trailing', 'dropped');
    return out.takeBytes();
  }

  Uint8List _packet(Uint8List packet) {
    final reader = YyReader(packet, 4);
    final uri = reader.u32();
    reader.u16();
    // The AP login answer repeats the uid as text (`KEY_YY_UID`); numbers
    // keep their length, so a text replacement leaves the lengths valid.
    if (_kept.contains(uri)) return _numbersReplaced(packet);
    switch (uri) {
      case _anonymousLoginReply:
        return _loginReply(reader);
      case _apLogin:
        // The connection UUID closes the auth block; the handshake URL
        // repeats it and gets the same replacement in [scrubUrl].
        final auth = YyReader(reader.bytes32())
          ..latin()
          ..latin()
          ..u32()
          ..u32()
          ..u32()
          ..latin()
          ..latin()
          ..latin()
          ..u32()
          ..u32()
          ..u32()
          ..u32();
        _uuid = names.secret(auth.latin());
        record('apLogin', 'secret');
        return YyProtocol.apLogin(
          YyAnonymousLogin(ok: true, uid: _uid, username: _username, password: _password, cookie: _cookie),
          uuid: _uuid,
        );
      case _router:
        record('joinChannel.uid', 'secret');
        return YyProtocol.join(uid: _uid, topSid: _topSid, subSid: _subSid, trace: 'F${_uid}_yymwebh5_0').first;
      case _subscribeApps:
        return YyProtocol.join(uid: _uid, topSid: _topSid, subSid: _subSid, trace: '').last;
      case _joinGroups:
        reader.u64();
        final groups = YyProtocol.groups(uid: _uid, topSid: _topSid, subSid: _subSid);
        return reader.u32() == 2 ? groups.last : groups.first;
      case _routerReply:
        return _routerAnswer(reader);
      case _groupMessage:
        final type = reader.u64();
        final group = reader.u64();
        final app = reader.u32();
        final message = reader.bytes32();
        return (YyWriter(_groupMessage)
              ..u64(type)
              ..u64(group)
              ..u32(app)
              ..bytes32(_service(app, message)))
            .take();
      case _bySidMessage:
        final app = reader.u16();
        final top = reader.u32();
        final message = reader.bytes16();
        return (YyWriter(_bySidMessage)
              ..u16(app)
              ..u32(top)
              ..bytes16(_service(app, message)))
            .take();
      default:
        record('uri.$uri', 'dropped');
        return YyWriter(uri).take();
    }
  }

  /// [packet] with every replaced number (5+ digits) written as text
  /// replaced by its pseudonym.
  Uint8List _numbersReplaced(Uint8List packet) {
    var text = latin1.decode(packet);
    var changed = false;
    for (final MapEntry(key: original, value: replacement) in names.pairs) {
      if (original.length < 5 || !RegExp(r'^\d+$').hasMatch(original) || !text.contains(original)) continue;
      text = text.replaceAll(RegExp('(?<![0-9])$original(?![0-9])'), replacement);
      changed = true;
    }
    if (changed) record('text.uid', 'person');
    return changed ? latin1.encode(text) : packet;
  }

  /// `778500`: the anonymous credentials, replaced and remembered for the
  /// client packets that repeat them.
  Uint8List _loginReply(YyReader reader) {
    final head = reader.latin();
    final envelope = reader.u32();
    final realUri = reader.u32();
    final payload = YyReader(reader.bytes32());
    final prefix = payload.latin();
    final result = payload.u32();
    final uid32 = payload.u32();
    final yyid = payload.u32();
    _username = names.secret(payload.latin());
    _password = names.secret(payload.latin());
    _cookie = _bytes(payload.bytes16());
    final ticket = _bytes(payload.bytes16());
    final tail1 = payload.latin();
    final tail2 = payload.latin();
    final uid64 = payload.remaining >= 8 ? payload.u64() : null;
    _uid = _digits(uid64 ?? uid32);
    record('anonymousLogin', 'secret');
    final rebuilt = YyWriter()
      ..latin(prefix)
      ..u32(result)
      ..u32(uid64 == null ? _uid : _digits(uid32))
      ..u32(_digits(yyid))
      ..latin(_username)
      ..latin(_password)
      ..bytes16(_cookie)
      ..bytes16(ticket)
      ..latin(tail1)
      ..latin(tail2);
    if (uid64 != null) rebuilt.u64(_uid);
    return (YyWriter(_anonymousLoginReply)
          ..latin(head)
          ..u32(envelope)
          ..u32(realUri)
          ..bytes32(rebuilt.take()))
        .take();
  }

  /// `512011`: the join answer keeps its fields with the uid replaced; any
  /// other routed answer loses its payload.
  Uint8List _routerAnswer(YyReader reader) {
    final head = reader.latin();
    final realUri = reader.u32();
    final code = reader.u16();
    final payload = YyReader(reader.bytes32());
    var body = const <int>[];
    if (realUri == _joinChannelReply && payload.remaining >= 21) {
      final top = payload.u32();
      final uid = payload.u32();
      final sub = payload.u32();
      final asid = payload.u32();
      final time = payload.u32();
      final status = payload.u8();
      final error = payload.bytes16();
      body =
          (YyWriter()
                ..u32(top)
                ..u32(_digits(uid))
                ..u32(sub)
                ..u32(asid)
                ..u32(time)
                ..u8(status)
                ..bytes16(error))
              .take();
      record('joinReply.uid', 'person');
    } else if (realUri == _groupMessage) {
      final type = payload.u64();
      final group = payload.u64();
      final app = payload.u32();
      body =
          (YyWriter()
                ..u64(type)
                ..u64(group)
                ..u32(app)
                ..bytes32(_service(app, payload.bytes32())))
              .take();
    } else {
      record('router.$realUri', 'dropped');
    }
    return (YyWriter(_routerReply)
          ..latin(head)
          ..u32(realUri)
          ..u16(code)
          ..bytes32(body))
        .take();
  }

  /// Application 31 text chat rebuilt with a pseudonymous sender and no
  /// extra items; other applications' messages emptied.
  List<int> _service(int app, Uint8List message) {
    if (app != 31 || message.length < 10) {
      record('app.$app', 'dropped');
      return const [];
    }
    final reader = YyReader(message, 4);
    final uri = reader.u32();
    reader.u16();
    if (uri != 3104600) {
      record('app31.$uri', 'dropped');
      return const [];
    }
    final uid = reader.u32();
    final top = reader.u32();
    final sub = reader.u32();
    final chat = reader.bytes16();
    final first = reader.bytes16();
    final second = reader.bytes16();
    final name = reader.remaining > 0 ? reader.utf8String() : '';
    record('chat.sender', 'person');
    return (YyWriter(3104600)
          ..u32(_digits(uid))
          ..u32(top)
          ..u32(sub)
          ..bytes16(chat)
          ..bytes16(first)
          ..bytes16(second)
          ..bytes16(utf8.encode(names.person(name)))
          ..u32(0))
        .take();
  }
}
