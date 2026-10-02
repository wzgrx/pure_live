import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/codec/protobuf.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:meta/meta.dart';

/// AcFun's danmaku connection (docs/D-弹幕/D01-平台弹幕协议/D01.10-AcFun弹幕/record.md): the web live
/// page's link (Kuaishou's live middle platform, `wss://link.xiatou.com/`)
/// over the shared WebSocket runtime. 3.x had no AcFun danmaku.
///
/// - The room's `AcfunDanmakuArgs` (M4.10) already hold the visitor session
///   and the broadcast's tickets from room entry, so connecting sends no HTTP
///   request. Without a usable `acSecurity` or tickets the start refreshes
///   them once (a new visitor session and `startPlay`), else it ends with
///   [DanmakuCloseReason.credentialsUnavailable].
/// - At every open: register (sealed with `acSecurity`); the answer brings
///   the session key; then a keep-alive and the enter-room command. The
///   enter-room answer joins ([DanmakuReady]); none within 10 s reconnects,
///   and a second timeout in a row refreshes the arguments as well.
/// - A room heartbeat every 10 s (the enter-room answer's interval), a
///   keep-alive with every fifth one (50 s), and every push acknowledged.
/// - A dead ticket moves to the next one on the same socket, as the web
///   client does; when every ticket failed since the last join, a refused
///   register or command, and a broadcast that closed, reopened or was
///   banned, refresh the arguments and reopen. A broadcast that is gone ends
///   with [DanmakuCloseReason.connectionFailed]; a refresh that fails, or
///   [maxRefreshes] of them without a join, with
///   [DanmakuCloseReason.credentialsUnavailable].
final class AcfunDanmakuConnection extends DanmakuSocketConnection<AcfunDanmakuArgs> {
  /// Creates the connection. [proxy] routes the socket; `connector` replaces
  /// `dart:io`'s handshake. [policy], [now] (the heartbeat's timestamp) and
  /// [random] (the payloads' IVs) are the platform's unless a test fixes
  /// them.
  new({super.proxy, super.connector, super.policy = defaultPolicy, DateTime Function()? now, Random? random})
    : _now = now ?? DateTime.now,
      _random = random ?? Random.secure(),
      super(site: SiteIds.acfun);

  /// The web client's timing: the 10 s room heartbeat the enter-room answer
  /// names (so 90 s of silence replaces the socket) and 10 s for the join.
  static const DanmakuSocketPolicy defaultPolicy = DanmakuSocketPolicy(
    heartbeatInterval: Duration(seconds: 10),
    joinTimeout: Duration(seconds: 10),
  );

  /// Heartbeats per keep-alive: 5 × 10 s, the web client's 50 s
  /// `heartBeatInterval`.
  static const int heartbeatsPerKeepAlive = 5;

  /// Refreshes of the arguments in a row without a join before the
  /// connection gives up.
  static const int maxRefreshes = 3;

  final DateTime Function() _now;
  final Random _random;
  _State? _state;

  @override
  @protected
  Future<DanmakuSocketTarget> target(AcfunDanmakuArgs args, DanmakuRun run) async {
    var current = args;
    var key = AcfunDanmakuProtocol.securityKey(current.visitor.security);
    if (key == null || current.tickets.isEmpty) {
      // A session without acSecurity (M4.10 keeps streams working without
      // it) or a broadcast without tickets: one new session and startPlay.
      final refresh = current.refresh;
      if (refresh == null) {
        throw const DanmakuStartFailure(DanmakuCloseReason.credentialsUnavailable, detail: 'No acSecurity or tickets');
      }
      try {
        current = await refresh();
      } on Object catch (error) {
        throw DanmakuStartFailure(_closeReason(error), detail: _refreshFailure(error));
      }
      key = AcfunDanmakuProtocol.securityKey(current.visitor.security);
      if (key == null || current.tickets.isEmpty) {
        throw const DanmakuStartFailure(DanmakuCloseReason.credentialsUnavailable, detail: 'No acSecurity or tickets');
      }
    }
    _state = _State(run, current, key);
    return _target(current);
  }

  static DanmakuSocketTarget _target(AcfunDanmakuArgs args) =>
      DanmakuSocketTarget(endpoints: [AcfunDanmakuProtocol.endpoint], headers: args.headers);

  _State? _of(DanmakuSocketSession session) {
    final state = _state;
    return state != null && identical(state.run, session.run) ? state : null;
  }

  @override
  @protected
  void onOpen(DanmakuSocketSession session) {
    final state = _of(session);
    if (state == null) return;
    final link = AcfunDanmakuLink(state.args, security: state.key, random: _random);
    state
      ..socket = _Socket(link)
      ..opens += 1;
    session.send(link.register());
  }

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    final state = _of(session);
    final socket = state?.socket;
    if (data is! List<int> || state == null || socket == null) return;
    final link = socket.link;
    final AcfunDanmakuPacket packet;
    try {
      packet = link.read(data);
    } on FormatException {
      // A frame that does not add up or does not open: dropped on its own.
      return;
    }
    switch (packet.command) {
      case AcfunDanmakuProtocol.registerCommand:
        if (packet.errorCode != 0 || !link.registered) {
          _refresh(session, state, 'Register refused (${packet.errorCode})');
          return;
        }
        session
          ..send(link.keepAlive())
          ..send(link.enterRoom(ticket: state.currentTicket, reconnects: state.opens - 1));
      case AcfunDanmakuProtocol.roomCommand:
        if (packet.errorCode != 0) {
          _refresh(session, state, 'Command refused (${packet.errorCode})');
          return;
        }
        final ({String type, int code, Uint8List payload}) ack;
        try {
          ack = AcfunDanmakuProtocol.ack(packet.payload);
        } on FormatException {
          return;
        }
        if (ack.code != 0) {
          _commandError(session, state, socket, ack.code);
        } else if (ack.type == AcfunDanmakuProtocol.enterRoomAck && !socket.joined) {
          socket.joined = true;
          state
            ..refreshes = 0
            ..ticketFailures = 0
            ..joinTimeouts = 0;
          session.ready();
        }
      case AcfunDanmakuProtocol.messageCommand:
        session.send(link.pushAck(packet));
        final push = AcfunDanmakuProtocol.push(packet.payload);
        for (final message in push.messages) {
          if (!session.isActive) return;
          session.message(message);
        }
        if (push.ticketInvalid) {
          _nextTicket(session, state, socket);
        } else if (AcfunDanmakuProtocol.refreshingStatuses.contains(push.statusChanged)) {
          _refresh(session, state, 'Broadcast status ${push.statusChanged}');
        }
      default:
        if (packet.command.startsWith(AcfunDanmakuProtocol.pushPrefix)) {
          session.send(link.pushAck(packet));
        } else if (packet.errorCode != 0) {
          _refresh(session, state, '${packet.command} refused (${packet.errorCode})');
        }
    }
  }

  /// No enter-room answer within 10 s: the first time the socket is replaced
  /// (a stalled socket), the second time in a row the arguments are
  /// refreshed too (a register answer that does not open, a ticket the
  /// server ignores).
  @override
  @protected
  void onJoinTimeout(DanmakuSocketSession session) {
    final state = _of(session);
    if (state == null) return;
    state.joinTimeouts += 1;
    if (state.joinTimeouts < 2) {
      session.reconnect();
    } else {
      state.joinTimeouts = 0;
      _refresh(session, state, 'Join timed out');
    }
  }

  /// An enter-room or heartbeat answer with an error: a dead ticket moves to
  /// the next one, anything else (the broadcast ended, started again, or an
  /// unknown code) refreshes the arguments.
  void _commandError(DanmakuSocketSession session, _State state, _Socket socket, int code) {
    if (AcfunDanmakuProtocol.ticketErrors.contains(code)) {
      _nextTicket(session, state, socket);
    } else {
      _refresh(session, state, 'Command error $code');
    }
  }

  /// The web client's answer to a dead ticket: enter again with the next
  /// one. Once every ticket failed since the last join, the arguments are
  /// refreshed instead.
  void _nextTicket(DanmakuSocketSession session, _State state, _Socket socket) {
    state.ticketFailures += 1;
    if (state.ticketFailures >= state.args.tickets.length) {
      _refresh(session, state, 'Every ticket failed');
      return;
    }
    state.ticket = (state.ticket + 1) % state.args.tickets.length;
    socket.joined = false;
    session
      ..markDisconnected()
      ..send(socket.link.enterRoom(ticket: state.currentTicket, reconnects: state.opens - 1));
  }

  /// A new visitor session and broadcast (`AcfunDanmakuArgs.refresh`), then
  /// a new socket with them. One refresh at a time; the socket in use keeps
  /// delivering until it is replaced.
  void _refresh(DanmakuSocketSession session, _State state, String reason) {
    if (state.refreshing || !session.isActive) return;
    if (state.refreshes >= maxRefreshes) {
      session.run.closed(DanmakuCloseReason.credentialsUnavailable, detail: reason);
      return;
    }
    state
      ..refreshing = true
      ..refreshes += 1;
    session
      ..cancelJoinTimeout()
      ..markDisconnected();
    unawaited(_reopen(session, state, reason));
  }

  Future<void> _reopen(DanmakuSocketSession session, _State state, String reason) async {
    try {
      final refresh = state.args.refresh;
      if (refresh == null) {
        session.run.closed(DanmakuCloseReason.credentialsUnavailable, detail: '$reason; no refresh');
        return;
      }
      final AcfunDanmakuArgs next;
      try {
        next = await refresh();
      } on Object catch (error) {
        if (session.isActive) session.run.closed(_closeReason(error), detail: '$reason; ${_refreshFailure(error)}');
        return;
      }
      if (!session.isActive) return;
      final key = AcfunDanmakuProtocol.securityKey(next.visitor.security);
      if (key == null || next.tickets.isEmpty) {
        session.run.closed(DanmakuCloseReason.credentialsUnavailable, detail: '$reason; no acSecurity or tickets');
        return;
      }
      state
        ..args = next
        ..key = key
        ..ticket = 0
        ..ticketFailures = 0;
      await session.reopen(_target(next));
    } finally {
      state.refreshing = false;
    }
  }

  /// A broadcast that is gone (`StreamUnavailable`: ended, or a paid show)
  /// cannot be joined; any other failure leaves the credentials unknown.
  static DanmakuCloseReason _closeReason(Object error) =>
      error is StreamUnavailable ? DanmakuCloseReason.connectionFailed : DanmakuCloseReason.credentialsUnavailable;

  /// The failure's kind only: the details of a request error can hold the
  /// visitor token of the URL.
  static String _refreshFailure(Object error) =>
      'refresh failed: ${error is SiteError ? error.kind : error.runtimeType}';

  @override
  @protected
  Object? heartbeatFrame(DanmakuSocketSession session) {
    final state = _of(session);
    final socket = state?.socket;
    if (state == null || socket == null || !socket.joined) return null;
    socket.heartbeats += 1;
    if (socket.heartbeats % heartbeatsPerKeepAlive == 0) session.send(socket.link.keepAlive());
    return socket.link.heartbeat(ticket: state.currentTicket, now: _now());
  }

  @override
  @protected
  Future<void> stop() async {
    _state = null;
    await super.stop();
  }
}

/// The state of one run: the arguments in use and the recovery budget.
final class _State {
  new(this.run, this.args, this.key);

  final DanmakuRun run;
  AcfunDanmakuArgs args;

  /// `acSecurity` of [args], decoded.
  Uint8List key;

  /// The ticket in use (an index into [args]'s tickets).
  int ticket = 0;

  /// Dead tickets since the last join.
  int ticketFailures = 0;

  /// Refreshes since the last join.
  int refreshes = 0;

  /// Join timeouts in a row.
  int joinTimeouts = 0;
  bool refreshing = false;

  /// Sockets opened in this run.
  int opens = 0;

  /// The current socket's link.
  _Socket? socket;

  String get currentTicket => args.tickets[ticket % args.tickets.length];
}

/// One socket: its link and whether it entered the room.
final class _Socket {
  new(this.link);

  final AcfunDanmakuLink link;
  bool joined = false;
  int heartbeats = 0;
}

/// One packet received on the link, opened ([AcfunDanmakuLink.read]).
@immutable
final class AcfunDanmakuPacket {
  /// Creates a packet.
  const new({required this.command, required this.seqId, required this.payload, this.errorCode = 0, this.error = ''});

  /// `DownstreamPayload.command`, like `Basic.Register`.
  final String command;

  /// The header's `seqId` (a push's acknowledgement echoes it).
  final int seqId;

  /// `payloadData`.
  final Uint8List payload;

  /// `errorCode`; 0 is success.
  final int errorCode;

  /// `errorMsg`.
  final String error;
}

/// What one `Push.ZtLiveInteractive.Message` carried: the messages to report,
/// whether the ticket died (`ZtLiveScTicketInvalid`) and the broadcast's new
/// status (`ZtLiveScStatusChanged.type`, or null).
typedef AcfunDanmakuPush = ({List<LiveMessage> messages, bool ticketInvalid, int? statusChanged});

/// AcFun's link protocol (spec/sites/acfun.md §7 of the archived v4, checked
/// against the recording `fixtures/acfun/danmaku/S07-live`), without I/O.
///
/// A frame is `0xABCD`, version 1, the header's and the payload's lengths
/// (big-endian `u16 u16 u32 u32`), then the protobuf `PacketHeader` (`appId
/// 1, uid 2, instanceId 3, decodedPayloadLen 7, encryptionMode 8, tokenInfo
/// 9, seqId 10, kpn 12`) and the payload: a 16-byte IV and the AES-128-CBC
/// ciphertext of an `UpstreamPayload` (`command 1, seqId 2, retryCount 3,
/// payloadData 4, subBiz 9`) or a `DownstreamPayload` (`command 1, seqId 2,
/// errorCode 3, payloadData 4, errorMsg 5`). Mode 1 is keyed by
/// `acSecurity` (the register exchange), mode 2 by the session key the
/// register answer brings.
abstract final class AcfunDanmakuProtocol {
  /// The link server.
  static final Uri endpoint = Uri.parse('wss://link.xiatou.com/');

  /// Frame magic.
  static const int magic = 0xABCD;

  /// Frame version.
  static const int version = 1;

  /// `PacketHeader.appId` of AcFun.
  static const int appId = 13;

  /// Product name (`kpn`).
  static const String kpn = 'ACFUN_APP';

  /// Product flavour (`kpf`).
  static const String kpf = 'PC_WEB';

  /// Business line (`subBiz`).
  static const String subBiz = 'mainApp';

  /// `clientLiveSdkVersion` of the enter-room command.
  static const String sdkVersion = 'kwai-acfun-live-link';

  /// Register command.
  static const String registerCommand = 'Basic.Register';

  /// Keep-alive command.
  static const String keepAliveCommand = 'Basic.KeepAlive';

  /// Room commands (enter room, heartbeat) and their answers.
  static const String roomCommand = 'Global.ZtLiveInteractive.CsCmd';

  /// Room messages.
  static const String messageCommand = 'Push.ZtLiveInteractive.Message';

  /// Prefix of the commands the server pushes (each one is acknowledged).
  static const String pushPrefix = 'Push.';

  /// The enter-room answer's type.
  static const String enterRoomAck = 'ZtLiveCsEnterRoomAck';

  /// Room-command error codes of a dead ticket (the web client's
  /// `handleAck`: it enters again with the next ticket). 1 is an ended
  /// broadcast, 8 a new one.
  static const Set<int> ticketErrors = {2, 3, 4, 7};

  /// `ZtLiveScStatusChanged.type`s that need new arguments: 1 the broadcast
  /// closed, 2 a new broadcast opened, 4 it was banned. 3 (new stream URLs)
  /// does not concern the chat.
  static const Set<int> refreshingStatuses = {1, 2, 4};

  static const int _aesBlock = 16;
  static const int _maxEpochMilliseconds = 8640000000000000;

  /// `acSecurity` decoded: the 16-byte key of the register exchange, or null
  /// when it is missing or not a Base64 AES-128 key.
  static Uint8List? securityKey(String? security) {
    if (security == null || security.isEmpty) return null;
    try {
      final key = base64.decode(security);
      return key.length == _aesBlock ? key : null;
    } on FormatException {
      return null;
    }
  }

  /// Wraps an encoded [header] and [payload] in a frame.
  static Uint8List frame(List<int> header, List<int> payload) {
    final out = Uint8List(12 + header.length + payload.length);
    ByteData.sublistView(out)
      ..setUint16(0, magic)
      ..setUint16(2, version)
      ..setUint32(4, header.length)
      ..setUint32(8, payload.length);
    out
      ..setAll(12, header)
      ..setAll(12 + header.length, payload);
    return out;
  }

  /// Splits a [frame] into its header and (still sealed) payload; throws
  /// [FormatException] without the magic or when the lengths do not add up.
  static ({ProtoMessage header, Uint8List payload}) unframe(List<int> frame) {
    final data = frame is Uint8List ? frame : Uint8List.fromList(frame);
    if (data.length < 12) throw const FormatException('AcFun frame shorter than its prefix');
    final view = ByteData.sublistView(data);
    if (view.getUint16(0) != magic) throw const FormatException('AcFun frame without its magic');
    final headerLength = view.getUint32(4);
    final payloadLength = view.getUint32(8);
    if (12 + headerLength + payloadLength != data.length) throw const FormatException('AcFun frame size mismatch');
    return (
      header: ProtoMessage.decode(Uint8List.sublistView(data, 12, 12 + headerLength)),
      payload: Uint8List.sublistView(data, 12 + headerLength),
    );
  }

  /// [plain] sealed under [key] with [iv]: the IV, then the ciphertext.
  static Uint8List seal(List<int> plain, List<int> key, List<int> iv) =>
      Uint8List.fromList([...iv, ...AesCbc.encrypt(plain, key: key, iv: iv)]);

  /// Opens a [seal]ed payload; throws [FormatException] when it is too short
  /// or does not decrypt (a wrong key).
  static Uint8List open(List<int> sealed, List<int> key) {
    if (sealed.length < 2 * _aesBlock) throw const FormatException('AcFun payload shorter than two blocks');
    return Aes128Cbc.decrypt(sealed.sublist(_aesBlock), key: key, iv: sealed.sublist(0, _aesBlock));
  }

  /// `ZtLiveCsCmdAck`: the answer's type, its error code and payload.
  static ({String type, int code, Uint8List payload}) ack(List<int> payload) {
    final message = ProtoMessage.decode(payload);
    return (type: message.string(1) ?? '', code: message.integer(2) ?? 0, payload: message.bytes(4) ?? Uint8List(0));
  }

  /// `ZtLiveCsEnterRoomAck.heartbeatIntervalMs`, or null when it is missing
  /// or not positive.
  static Duration? heartbeatInterval(List<int> enterRoomAck) {
    final millis = ProtoMessage.decode(enterRoomAck).integer(1) ?? 0;
    return millis > 0 ? Duration(milliseconds: millis) : null;
  }

  /// One `ZtLiveScMessage` (`messageType 1, compressionType 2 (2 is gzip),
  /// payload 3, liveId 4, ticket 5, serverTimestampMs 6`):
  ///
  /// - `ZtLiveScActionSignal` (`{1: [{1 signalType, 2: [payload]}]}`): each
  ///   `CommonActionSignalComment` is a chat;
  /// - `ZtLiveScStateSignal` (`{1: [{1 signalType, 2 payload}]}`): each
  ///   `CommonStateSignalDisplayInfo` is the concurrent audience;
  /// - `ZtLiveScTicketInvalid` and `ZtLiveScStatusChanged` are flagged.
  ///
  /// Everything else (likes, entries, follows, gifts, the banana count, the
  /// recent comments of room entry, notify signals) is not shown, as on
  /// every 3.x platform. A signal (or one of its payloads) that does not
  /// decode is skipped on its own; a message or signal list that does not
  /// decode (or gunzip) yields nothing.
  static AcfunDanmakuPush push(List<int> payload) {
    const none = (messages: <LiveMessage>[], ticketInvalid: false, statusChanged: null);
    final messages = <LiveMessage>[];
    try {
      final message = ProtoMessage.decode(payload);
      var body = message.bytes(3) ?? Uint8List(0);
      if (message.integer(2) == 2) body = Uint8List.fromList(gzip.decode(body));
      switch (message.string(1)) {
        case 'ZtLiveScActionSignal':
          for (final item in _signals(body)) {
            if (item.string(1) != 'CommonActionSignalComment') continue;
            for (final field in item.fields) {
              if (field.number != 2 || field.wireType != ProtoMessage.lengthDelimitedType) continue;
              if (_comment(field.value as Uint8List) case final chat?) messages.add(chat);
            }
          }
        case 'ZtLiveScStateSignal':
          for (final item in _signals(body)) {
            if (item.string(1) != 'CommonStateSignalDisplayInfo') continue;
            if (_displayInfo(item.bytes(2)) case final audience?) messages.add(audience);
          }
        case 'ZtLiveScTicketInvalid':
          return (messages: messages, ticketInvalid: true, statusChanged: null);
        case 'ZtLiveScStatusChanged':
          return (messages: messages, ticketInvalid: false, statusChanged: ProtoMessage.decode(body).integer(1) ?? 0);
      }
    } on FormatException {
      return none;
    }
    return (messages: messages, ticketInvalid: false, statusChanged: null);
  }

  /// The signals of an action or state signal list (`{1: [signal]}`), each
  /// read on its own; one that does not decode is left out.
  static List<ProtoMessage> _signals(Uint8List body) {
    final signals = <ProtoMessage>[];
    for (final field in ProtoMessage.decode(body).fields) {
      if (field.number != 1 || field.wireType != ProtoMessage.lengthDelimitedType) continue;
      try {
        signals.add(ProtoMessage.decode(field.value as Uint8List));
      } on FormatException {
        continue;
      }
    }
    return signals;
  }

  /// `CommonActionSignalComment` (`content 1, sendTimeMs 2, userInfo 3
  /// {userId 1, nickname 2}`); none without text or sender.
  static LiveMessage? _comment(Uint8List payload) {
    try {
      final signal = ProtoMessage.decode(payload);
      final text = signal.string(1) ?? '';
      final user = signal.message(3);
      if (text.isEmpty || user == null) return null;
      final id = user.integer(1);
      final millis = signal.integer(2);
      return LiveMessage(
        type: LiveMessageType.chat,
        userName: user.string(2) ?? '',
        userId: id == null || id <= 0 ? '' : '$id',
        message: text,
        color: LiveMessageColor.white,
        sentAt: millis == null || millis <= 0 || millis > _maxEpochMilliseconds
            ? null
            : DateTime.fromMillisecondsSinceEpoch(millis),
      );
    } on FormatException {
      return null;
    }
  }

  /// `CommonStateSignalDisplayInfo.watchingCount` (text like `76` or `1.2万`;
  /// `live/info`'s `onlineCount` at the same moment): concurrent viewers.
  static LiveMessage? _displayInfo(Uint8List? payload) {
    if (payload == null) return null;
    try {
      final watching = parseChineseCount(ProtoMessage.decode(payload).string(1));
      if (watching == null) return null;
      return LiveMessage(
        type: LiveMessageType.online,
        userName: '',
        message: '',
        color: LiveMessageColor.white,
        data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.onlineViewers, value: watching),
      );
    } on FormatException {
      return null;
    }
  }
}

/// The link of one socket: sequence numbers, the instance id and the
/// session key the register answer brings, and the frames of the web
/// client (register, keep-alive, enter room, heartbeat, push
/// acknowledgement).
final class AcfunDanmakuLink {
  /// Starts a link for [args]; [security] is its decoded `acSecurity`
  /// ([AcfunDanmakuProtocol.securityKey]) and [random] draws the IVs.
  new(this.args, {required List<int> security, Random? random})
    : _security = Uint8List.fromList(security),
      _random = random ?? Random.secure(),
      _uid = int.tryParse(args.visitor.userId) ?? 0;

  /// The arguments.
  final AcfunDanmakuArgs args;

  final Uint8List _security;
  final Random _random;
  final int _uid;
  int _seq = 1;
  int _instanceId = 0;
  int _heartbeat = 0;
  Uint8List? _sessionKey;

  /// Whether the register answer brought the session key.
  bool get registered => _sessionKey != null;

  /// `Basic.Register`, sealed with `acSecurity`, the service token in the
  /// header: `RegisterRequest {appInfo 1 {sdkVersion "link-sdk", linkVersion
  /// "1.2.1"}, deviceInfo 2 {platformType 6 (H5), deviceModel "h5", did 5},
  /// presenceStatus 4 1, appActiveStatus 5 1, instanceId 8 0, ztCommonInfo
  /// 11 {kpn, kpf, uid 4, did 5}}`.
  Uint8List register() {
    final request = ProtoWriter()
      ..bytes(
        1,
        (ProtoWriter()
              ..string(1, 'link-sdk')
              ..string(4, '1.2.1'))
            .toBytes(),
      )
      ..bytes(
        2,
        (ProtoWriter()
              ..integer(1, 6)
              ..string(3, 'h5')
              ..string(5, args.visitor.deviceId))
            .toBytes(),
      )
      ..integer(4, 1)
      ..integer(5, 1)
      ..integer(8, 0)
      ..bytes(
        11,
        (ProtoWriter()
              ..string(1, AcfunDanmakuProtocol.kpn)
              ..string(2, AcfunDanmakuProtocol.kpf)
              ..integer(4, _uid)
              ..string(5, args.visitor.deviceId))
            .toBytes(),
      );
    return _send(AcfunDanmakuProtocol.registerCommand, request.toBytes(), serviceToken: true);
  }

  /// `Basic.KeepAlive {presenceStatus 1, appActiveStatus 1}`.
  Uint8List keepAlive() => _send(
    AcfunDanmakuProtocol.keepAliveCommand,
    (ProtoWriter()
          ..integer(1, 1)
          ..integer(2, 1))
        .toBytes(),
  );

  /// Enters the room with [ticket]: `ZtLiveCsEnterRoom {isAuthor 1 false,
  /// reconnectCount 2, enterRoomAttach 4, clientLiveSdkVersion 5}`.
  Uint8List enterRoom({required String ticket, int reconnects = 0}) => _command(
    'ZtLiveCsEnterRoom',
    (ProtoWriter()
          ..integer(1, 0)
          ..integer(2, reconnects)
          ..string(4, args.enterRoomAttach)
          ..string(5, AcfunDanmakuProtocol.sdkVersion))
        .toBytes(),
    ticket,
  );

  /// The next room heartbeat: `ZtLiveCsHeartbeat {clientTimestampMs 1,
  /// sequence 2}`, the sequence counting from 0 on this link.
  Uint8List heartbeat({required String ticket, required DateTime now}) => _command(
    'ZtLiveCsHeartbeat',
    (ProtoWriter()
          ..integer(1, now.millisecondsSinceEpoch)
          ..integer(2, _heartbeat++))
        .toBytes(),
    ticket,
  );

  /// The acknowledgement of [push]: its command without payload, the header
  /// carrying the push's sequence id; the link's own sequence does not move.
  Uint8List pushAck(AcfunDanmakuPacket push) => _send(push.command, null, headerSeq: push.seqId, advance: false);

  /// `ZtLiveCsCmd {cmdType 1, payload 2, ticket 3, liveId 4}`.
  Uint8List _command(String type, List<int> payload, String ticket) => _send(
    AcfunDanmakuProtocol.roomCommand,
    (ProtoWriter()
          ..string(1, type)
          ..bytes(2, payload)
          ..string(3, ticket)
          ..string(4, args.liveId))
        .toBytes(),
  );

  Uint8List _send(String command, List<int>? data, {bool serviceToken = false, int? headerSeq, bool advance = true}) {
    final upstream = ProtoWriter()
      ..string(1, command)
      ..integer(2, _seq)
      ..integer(3, 1);
    if (data != null) upstream.bytes(4, data);
    upstream.string(9, AcfunDanmakuProtocol.subBiz);
    final plain = upstream.toBytes();
    final key = serviceToken ? _security : _sessionKey;
    if (key == null) throw StateError('AcFun link: $command before the register answer');
    final header = ProtoWriter()
      ..integer(1, AcfunDanmakuProtocol.appId)
      ..integer(2, _uid)
      ..integer(3, _instanceId)
      ..integer(7, plain.length)
      ..integer(8, serviceToken ? 1 : 2);
    if (serviceToken) {
      header.bytes(
        9,
        (ProtoWriter()
              ..integer(1, 1)
              ..string(2, args.visitor.token))
            .toBytes(),
      );
    }
    header
      ..integer(10, headerSeq ?? _seq)
      ..string(12, AcfunDanmakuProtocol.kpn);
    if (advance) _seq++;
    final iv = Uint8List.fromList(List.generate(16, (_) => _random.nextInt(256)));
    return AcfunDanmakuProtocol.frame(header.toBytes(), AcfunDanmakuProtocol.seal(plain, key, iv));
  }

  /// Opens one received [frame]. The register answer's session key and
  /// instance id are kept for everything after it. Throws [FormatException]
  /// for a frame that does not add up or open (a wrong key included).
  AcfunDanmakuPacket read(List<int> frame) {
    final (:header, :payload) = AcfunDanmakuProtocol.unframe(frame);
    final plain = switch (header.integer(8) ?? 0) {
      0 => payload,
      1 => AcfunDanmakuProtocol.open(payload, _security),
      2 => AcfunDanmakuProtocol.open(
        payload,
        _sessionKey ?? (throw const FormatException('AcFun frame before the session key')),
      ),
      final mode => throw FormatException('AcFun encryption mode $mode'),
    };
    final down = ProtoMessage.decode(plain);
    final packet = AcfunDanmakuPacket(
      command: down.string(1) ?? '',
      seqId: header.integer(10) ?? 0,
      payload: down.bytes(4) ?? Uint8List(0),
      errorCode: down.integer(3) ?? 0,
      error: down.string(5) ?? '',
    );
    if (packet.command == AcfunDanmakuProtocol.registerCommand && packet.errorCode == 0) {
      final answer = ProtoMessage.decode(packet.payload);
      final key = answer.bytes(2);
      if (key != null && key.length == AcfunDanmakuProtocol._aesBlock) {
        _sessionKey = Uint8List.fromList(key);
        _instanceId = answer.integer(3) ?? 0;
      }
    }
    return packet;
  }
}
