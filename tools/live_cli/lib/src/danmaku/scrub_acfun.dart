import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:live_cli/src/danmaku/frame_scrub.dart';
import 'package:live_cli/src/danmaku/recorder.dart';
import 'package:live_danmaku/live_danmaku.dart';

/// AcFun (spec/sites/acfun.md §11): the visitor session (user id, device
/// id, service token, `acSecurity`), the room tickets and `enterRoomAttach`
/// are replaced; the link frames are opened with the real keys, scrubbed and
/// sealed again with replacement keys, so the fixture still decodes with
/// the real protocol code. Senders get pseudonyms; signals the connector
/// does not read keep their type and lose their payload; `startPlay` keeps
/// only what the chat start reads (the stream URLs are in the HTTP samples).
class AcfunFrameScrubber extends FrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  // Original keys, learned from the capture; replacements for the fixture.
  Uint8List? _security;
  Uint8List? _sessionKey;
  Uint8List? _fakeSecurity;
  Uint8List? _fakeSessionKey;

  // Keys for [plain], which walks the scrubbed frames again from the start.
  Uint8List? _plainSessionKey;

  /// IVs of the resealed frames: fixed, so a capture scrubs the same way.
  final Random _ivs = Random(7);

  static const _users = {
    'CommonActionSignalComment': 3,
    'CommonActionSignalLike': 1,
    'CommonActionSignalUserEnterRoom': 1,
    'CommonActionSignalUserFollowAuthor': 1,
    'CommonActionSignalGift': 1,
    'AcfunActionSignalThrowBanana': 1,
  };

  static const _keptStates = {'CommonStateSignalDisplayInfo', 'AcfunStateSignalDisplayInfo'};

  @override
  Uri scrubUrl(Uri url) {
    final query = url.queryParameters;
    if (!query.containsKey('acfun.api.visitor_st')) return url;
    record('url.visitor', 'secret');
    return url.replace(
      queryParameters: {
        for (final MapEntry(:key, :value) in query.entries)
          key: switch (key) {
            'userId' => names.digits(value),
            'did' || 'acfun.api.visitor_st' => names.secret(value),
            _ => value,
          },
      },
    );
  }

  /// A key of the same length, derived from the shape-keeping replacement
  /// of its hex form.
  Uint8List _key(List<int> original) {
    final shaped = names.secret([for (final byte in original) byte.toRadixString(16).padLeft(2, '0')].join());
    int nibble(int unit) => unit <= 0x39 ? unit - 0x30 : (unit - 0x61) % 16;
    return Uint8List.fromList([
      for (var i = 0; i + 1 < shaped.length; i += 2)
        (nibble(shaped.codeUnitAt(i)) << 4) | nibble(shaped.codeUnitAt(i + 1)),
    ]);
  }

  @override
  List<int>? scrubFrame(CapturedFrame frame) {
    final url = frame.url;
    if (url != null) return utf8.encode(_http(url, utf8.decode(frame.bytes)));
    return _link(frame.bytes, incoming: frame.direction == 'in');
  }

  String _http(Uri url, String body) {
    final root = jsonDecode(body);
    if (root is! Map<String, dynamic>) return body;
    if (root.containsKey('host')) {
      root['host'] = names.secret('${root['host']}');
      record(r'http.$.host', 'secret');
    }
    if (url.path.endsWith('/visitor/login')) {
      final security = root['acSecurity'];
      if (security is String) {
        _security = base64.decode(security);
        _fakeSecurity = _key(_security!);
        root['acSecurity'] = base64.encode(_fakeSecurity!);
      }
      if (root['userId'] != null) root['userId'] = int.parse(names.digits('${root['userId']}'));
      final token = root['acfun.api.visitor_st'];
      if (token is String) root['acfun.api.visitor_st'] = names.secret(token);
      record('visitor/login', 'secret');
    } else if (url.path.endsWith('/startPlay')) {
      final data = root['data'];
      if (data is Map<String, dynamic>) {
        root['data'] = {
          'liveId': data['liveId'],
          'availableTickets': [
            for (final ticket in data['availableTickets'] as List? ?? const []) names.secret('$ticket'),
          ],
          'enterRoomAttach': names.secret('${data['enterRoomAttach'] ?? ''}'),
        };
        record('startPlay.data', 'secret');
        record('startPlay.videoPlayRes', 'dropped');
      }
    }
    return jsonEncode(root);
  }

  List<int>? _link(List<int> bytes, {required bool incoming}) {
    final (:header, :payload) = AcfunProtocol.unframe(bytes);
    final mode = header.integer(8) ?? 0;
    final (key, fake) = switch (mode) {
      1 => (_security, _fakeSecurity),
      2 => (_sessionKey, _fakeSessionKey),
      _ => (null, null),
    };
    if (mode != 0 && (key == null || fake == null)) {
      record('frame.unkeyed', 'dropped');
      return null;
    }
    final plain = key == null ? payload : AcfunProtocol.open(payload, key);
    final scrubbed = _envelope(ProtoMessage.decode(plain), incoming: incoming);
    final rebuilt = ProtoWriter();
    for (final field in header.fields) {
      switch (field.number) {
        case 2:
          rebuilt.integer(2, int.parse(names.digits('${field.value}')));
        case 7:
          rebuilt.integer(7, scrubbed.length);
        case 9:
          final token = ProtoMessage.decode(field.value as Uint8List);
          final value = token.bytes(2);
          rebuilt.bytes(
            9,
            (ProtoWriter()
                  ..integer(1, token.integer(1) ?? 1)
                  ..string(2, names.secret(latin1.decode(value ?? const []))))
                .toBytes(),
          );
          record('header.tokenInfo', 'secret');
        default:
          rebuilt.field(field);
      }
    }
    final sealed = fake == null ? scrubbed : _seal(scrubbed, fake);
    return AcfunProtocol.frame(rebuilt.toBytes(), sealed);
  }

  Uint8List _seal(List<int> plain, List<int> key) {
    final iv = Uint8List.fromList(List.generate(16, (_) => _ivs.nextInt(256)));
    return Uint8List.fromList([...iv, ...AesCbc(key).encrypt(plain, iv)]);
  }

  /// Upstream or downstream payload: field 1 command, 4 the payload data.
  Uint8List _envelope(ProtoMessage envelope, {required bool incoming}) {
    final command = envelope.string(1) ?? '';
    final data = envelope.bytes(4);
    final out = ProtoWriter();
    for (final field in envelope.fields) {
      if (field.number == 4 && data != null) {
        out.bytes(4, _data(command, data, incoming: incoming));
      } else {
        out.field(field);
      }
    }
    return out.toBytes();
  }

  List<int> _data(String command, Uint8List data, {required bool incoming}) {
    final message = ProtoMessage.decode(data);
    switch ((command, incoming)) {
      case (AcfunProtocol.register, false):
        return _rewrite(message, {
          2: (field) => _rewrite(ProtoMessage.decode(field.value as Uint8List), {5: _secretField}),
          11: (field) => _rewrite(ProtoMessage.decode(field.value as Uint8List), {4: _digitsField, 5: _secretField}),
        });
      case (AcfunProtocol.register, true):
        final key = message.bytes(2);
        if (key != null) {
          _sessionKey = Uint8List.fromList(key);
          _fakeSessionKey = _key(key);
        }
        record('register.answer', 'secret');
        return _rewrite(message, {2: (_) => _fakeSessionKey!}, keep: const {2, 3});
      case (AcfunProtocol.keepAlive, true):
        // Access points are dropped; the server time stays.
        return _rewrite(message, const {}, keep: const {2});
      case (AcfunProtocol.roomCommand, false):
        final enter = message.string(1) == 'ZtLiveCsEnterRoom';
        record('command.ticket', 'secret');
        return _rewrite(message, {
          2: (field) => enter
              ? _rewrite(ProtoMessage.decode(field.value as Uint8List), {4: _secretField})
              : field.value as Uint8List,
          3: _secretField,
        });
      case (AcfunProtocol.message, true):
        return _rewrite(message, {3: (field) => _push(message, field.value as Uint8List), 5: _secretField});
      case (_, true) when command != AcfunProtocol.roomCommand:
        record('command.$command', 'dropped');
        return const [];
      default:
        return data;
    }
  }

  List<int> _push(ProtoMessage message, Uint8List payload) {
    final zipped = message.integer(2) == 2;
    final body = ProtoMessage.decode(zipped ? gzip.decode(payload) : payload);
    final type = message.string(1);
    final out = switch (type) {
      'ZtLiveScActionSignal' || 'ZtLiveScStateSignal' || 'ZtLiveScNotifySignal' => _rewrite(body, {
        1: (field) => _item(type!, ProtoMessage.decode(field.value as Uint8List)),
      }),
      _ => zipped ? gzip.decode(payload) : payload,
    };
    return zipped ? gzip.encode(out) : out;
  }

  Uint8List _item(String type, ProtoMessage item) {
    final signal = item.string(1) ?? '';
    final user = _users[signal];
    final kept = type == 'ZtLiveScStateSignal' && _keptStates.contains(signal);
    if (!kept && (type != 'ZtLiveScActionSignal' || user == null)) record('signal.$signal', 'dropped');
    return _rewrite(item, {
      2: (field) {
        if (kept) return field.value as Uint8List;
        if (type != 'ZtLiveScActionSignal' || user == null) return Uint8List(0);
        return _rewrite(ProtoMessage.decode(field.value as Uint8List), {user: _user});
      },
    });
  }

  /// A sender: the id and name replaced; the avatar and custom data
  /// dropped.
  Uint8List _user(ProtoField field) {
    record('signal.user', 'person');
    return _rewrite(
      ProtoMessage.decode(field.value as Uint8List),
      {1: _digitsField, 2: (field) => utf8.encode(names.person(utf8.decode(field.value as Uint8List)))},
      keep: const {1, 2, 5},
    );
  }

  Uint8List _secretField(ProtoField field) =>
      utf8.encode(names.secret(utf8.decode(field.value as Uint8List, allowMalformed: true)));

  int _digitsField(ProtoField field) => int.parse(names.digits('${field.value}'));

  /// [message] with the fields in [replace] rewritten (a byte list or an
  /// int), fields outside [keep] (when given) dropped, the rest copied.
  Uint8List _rewrite(ProtoMessage message, Map<int, Object Function(ProtoField)> replace, {Set<int>? keep}) {
    final out = ProtoWriter();
    for (final field in message.fields) {
      if (keep != null && !keep.contains(field.number)) continue;
      final rewrite = replace[field.number];
      if (rewrite == null) {
        out.field(field);
        continue;
      }
      switch (rewrite(field)) {
        case final int value:
          out.integer(field.number, value);
        case final List<int> value:
          out.bytes(field.number, value);
      }
    }
    return out.toBytes();
  }

  @override
  List<int> plain(CapturedFrame frame) {
    if (frame.url != null) return frame.bytes;
    final (:header, :payload) = AcfunProtocol.unframe(frame.bytes);
    final key = switch (header.integer(8)) {
      1 => _fakeSecurity,
      2 => _plainSessionKey,
      _ => null,
    };
    final opened = key == null || payload.isEmpty ? payload : AcfunProtocol.open(payload, key);
    final envelope = ProtoMessage.decode(opened);
    final data = envelope.bytes(4) ?? Uint8List(0);
    final command = envelope.string(1);
    if (command == AcfunProtocol.register && frame.direction == 'in') {
      _plainSessionKey = ProtoMessage.decode(data).bytes(2);
    }
    if (command == AcfunProtocol.message) {
      final message = ProtoMessage.decode(data);
      final body = message.bytes(3) ?? Uint8List(0);
      return [...opened, ...(message.integer(2) == 2 ? gzip.decode(body) : body)];
    }
    return opened;
  }
}
