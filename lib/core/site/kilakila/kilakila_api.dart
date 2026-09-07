import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pure_live/core/common/http_client.dart';

enum KilakilaFailure {
  transport,
  access,
  rateLimited,
  notFound,
  service,
  schema,
  cancelled,
  historicalReplay,
  restricted,
  stateUnsupported,
  mediaUnavailable,
}

class KilakilaException implements Exception {
  const KilakilaException(this.kind);
  final KilakilaFailure kind;
  @override
  String toString() => 'Kilakila ${kind.name}';
}

typedef KilakilaRequest = Future<({int status, String body})> Function(Uri uri, CancelToken? cancel);

/// A current room/broadcast and its distinct owner. Neither a share room ID nor
/// an unknown status is promoted to a permanent channel identity/offline state.
class KilakilaRoomSnapshot {
  KilakilaRoomSnapshot({
    required this.roomId,
    required this.userId,
    required this.title,
    required this.nick,
    required this.cover,
    required this.avatar,
    required this.statusCode,
    required this.goldPrice,
    required this.watchNumber,
    Map<String, String> media = const {},
  }) : media = Map.unmodifiable(media);

  final String roomId;
  final String userId;
  final String title;
  final String nick;
  final String cover;
  final String avatar;
  final int statusCode;
  final int goldPrice;
  // Keep the platform field name until its audience semantics are verified.
  final int? watchNumber;
  final Map<String, String> media;
  bool get isLive => statusCode == 4;
  String get link => '${KilakilaApi.origin}/room/$roomId';
}

class KilakilaDirectoryPage {
  KilakilaDirectoryPage({required Iterable<KilakilaRoomSnapshot> rooms, required this.page, required this.hasMore})
    : rooms = List.unmodifiable(rooms);
  final List<KilakilaRoomSnapshot> rooms;
  final int page;
  final bool hasMore;
}

/// Anonymous official website contracts. Deliberately not registered as a
/// LiveSite until cross-broadcast identity, sharing and application integration
/// have their own evidence. No raw response/push-flow URL is retained in DTOs.
class KilakilaApi {
  KilakilaApi({KilakilaRequest? request}) : _request = request ?? _defaultRequest;
  static const origin = 'https://live.kilakila.cn';
  static const responseLimit = 1024 * 1024;
  static const playHeaders = {'Referer': '$origin/', 'User-Agent': 'Mozilla/5.0'};
  final KilakilaRequest _request;

  static Future<({int status, String body})> _defaultRequest(Uri uri, CancelToken? cancel) async {
    final response = await HttpClient.instance.dio.get<ResponseBody>(
      uri.toString(),
      cancelToken: cancel,
      options: Options(
        responseType: ResponseType.stream,
        headers: playHeaders,
        followRedirects: false,
        receiveTimeout: const Duration(seconds: 20),
        validateStatus: (_) => true,
      ),
    );
    final body = response.data;
    if (body == null) throw const KilakilaException(KilakilaFailure.schema);
    if (response.statusCode != 200) {
      await body.stream.listen((_) {}).cancel();
      return (status: response.statusCode ?? 0, body: '');
    }
    return (status: 200, body: await readBody(body.stream));
  }

  static Future<String> readBody(Stream<List<int>> stream, {Duration timeout = const Duration(seconds: 20)}) async {
    final iterator = StreamIterator(stream);
    final bytes = BytesBuilder(copy: false);
    final watch = Stopwatch()..start();
    try {
      while (true) {
        final remaining = timeout - watch.elapsed;
        if (remaining <= Duration.zero) throw TimeoutException('Kilakila response deadline');
        if (!await iterator.moveNext().timeout(remaining)) break;
        final chunk = iterator.current;
        if (bytes.length + chunk.length > responseLimit) throw const KilakilaException(KilakilaFailure.schema);
        bytes.add(chunk);
      }
      return utf8.decode(bytes.takeBytes());
    } on FormatException {
      throw const KilakilaException(KilakilaFailure.schema);
    } finally {
      watch.stop();
      await iterator.cancel();
    }
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
    required bool wrapped,
    CancelToken? cancel,
  }) async {
    if (cancel?.isCancelled == true) throw const KilakilaException(KilakilaFailure.cancelled);
    late final ({int status, String body}) response;
    try {
      response = await _request(Uri.parse('$origin$path').replace(queryParameters: query), cancel);
    } catch (error) {
      if (cancel?.isCancelled == true) throw const KilakilaException(KilakilaFailure.cancelled);
      if (error is KilakilaException) rethrow;
      throw const KilakilaException(KilakilaFailure.transport);
    }
    if (cancel?.isCancelled == true) throw const KilakilaException(KilakilaFailure.cancelled);
    final failure = switch (response.status) {
      200 => null,
      401 || 403 => KilakilaFailure.access,
      404 => KilakilaFailure.notFound,
      429 => KilakilaFailure.rateLimited,
      >= 500 => KilakilaFailure.service,
      _ => KilakilaFailure.transport,
    };
    if (failure != null) throw KilakilaException(failure);
    if (response.body.length > responseLimit || utf8.encode(response.body).length > responseLimit) {
      throw const KilakilaException(KilakilaFailure.schema);
    }
    try {
      var result = _object(jsonDecode(response.body));
      if (wrapped) {
        _businessCode(result['code']);
        result = _object(_object(result['data'])['body']);
      }
      final header = _object(result['h']);
      _businessCode(header['code'], roomDetail: !wrapped && path == '/LiveRoom/getRoomInfo');
      if (header['success'] != true) throw const KilakilaException(KilakilaFailure.schema);
      return result;
    } on FormatException {
      throw const KilakilaException(KilakilaFailure.schema);
    }
  }

  static void _businessCode(Object? value, {bool roomDetail = false}) {
    final code = _integer(value);
    if (code == null) throw const KilakilaException(KilakilaFailure.schema);
    if (roomDetail && code == 5966) throw const KilakilaException(KilakilaFailure.historicalReplay);
    if (code != 200) throw const KilakilaException(KilakilaFailure.service);
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) throw const KilakilaException(KilakilaFailure.schema);
    return Map<String, dynamic>.from(value);
  }

  static List<Map<String, dynamic>> _rows(Object? value) {
    if (value is! List || value.length > 1000) throw const KilakilaException(KilakilaFailure.schema);
    return value.map(_object).toList();
  }

  static String _text(Object? value) => value is String ? value.trim() : '';
  static int? _integer(Object? value) => value is int
      ? value
      : value is String
      ? int.tryParse(value)
      : null;
  static int _nonnegative(Object? value) {
    final number = _integer(value);
    if (number == null || number < 0) throw const KilakilaException(KilakilaFailure.schema);
    return number;
  }

  static String id(String value) {
    if (!RegExp(r'^[1-9][0-9]{0,31}$').hasMatch(value)) throw const KilakilaException(KilakilaFailure.schema);
    return value;
  }

  static String _id(Object? value) {
    // JSON numbers above JS's exact range may already be rounded upstream.
    if (value is int && value > 0 && value <= 9007199254740991) return '$value';
    if (value is String) return id(value);
    throw const KilakilaException(KilakilaFailure.schema);
  }

  static String? numericRoomFromUri(Uri uri) {
    if (!{'http', 'https'}.contains(uri.scheme) ||
        !{'live.kilakila.cn', 'www.hongdoufm.com'}.contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
      return null;
    }
    try {
      // Opaque/signed links remain a separate, unimplemented contract. Never
      // accidentally treat the encoded payload as a durable numeric room ID.
      final query = uri.queryParametersAll;
      if (query.containsKey('_specific_parameter')) return null;
      if (uri.pathSegments.length == 2 && uri.pathSegments.first == 'room' && !query.containsKey('id')) {
        return id(uri.pathSegments.last);
      }
      if (uri.path == '/PcLive/index/detail' && query['id']?.length == 1) return id(query['id']!.single);
    } on FormatException {
      return null;
    } on KilakilaException {
      return null;
    }
    return null;
  }

  static String _picture(Object? value) {
    final text = _text(value);
    final uri = Uri.tryParse(text);
    return uri != null && {'http', 'https'}.contains(uri.scheme) && uri.host.isNotEmpty && uri.userInfo.isEmpty
        ? text
        : '';
  }

  static String? mediaUrl(Object? value, {required String roomId, required String protocol}) {
    if (!{'flv', 'hls'}.contains(protocol)) return null;
    final text = _text(value);
    if (text.length > 8192) return null;
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'pull.live.hongrenshuo.com.cn' ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        uri.path != '/hrs/${id(roomId)}.${protocol == 'flv' ? 'flv' : 'm3u8'}') {
      return null;
    }
    try {
      final auth = uri.queryParametersAll['auth_key'];
      if (auth?.length != 1 || auth!.single.isEmpty || auth.single.length > 1024) return null;
      return text;
    } on FormatException {
      return null;
    }
  }

  static KilakilaRoomSnapshot _snapshot(
    Map<String, dynamic> room,
    Map<String, dynamic> owner, {
    bool playback = false,
  }) {
    final roomId = _id(room['roomIdStr']);
    final userId = _id(room['uid']);
    if (_id(owner['id']) != userId || _text(room['title']).isEmpty || _text(owner['nickname']).isEmpty) {
      throw const KilakilaException(KilakilaFailure.schema);
    }
    final status = _nonnegative(room['status']);
    final price = _nonnegative(room['goldPrice']);
    final media = <String, String>{};
    if (playback) {
      if (price != 0) throw const KilakilaException(KilakilaFailure.restricted);
      if (status != 4) throw const KilakilaException(KilakilaFailure.stateUnsupported);
      for (final entry in {'flv': 'flvPlayUrl', 'hls': 'hlsPlayUrl'}.entries) {
        final url = mediaUrl(room[entry.value], roomId: roomId, protocol: entry.key);
        if (url != null) media[entry.key] = url;
      }
      if (media.isEmpty) throw const KilakilaException(KilakilaFailure.mediaUnavailable);
    }
    final watching = _integer(room['watchNumber']);
    final cover = _picture(room['backPic']);
    return KilakilaRoomSnapshot(
      roomId: roomId,
      userId: userId,
      title: _text(room['title']),
      nick: _text(owner['nickname']),
      cover: cover.isNotEmpty ? cover : _picture(room['defaultBackgroundPicUrl']),
      avatar: _picture(owner['headPortraitUrl']),
      statusCode: status,
      goldPrice: price,
      watchNumber: watching != null && watching >= 0 ? watching : null,
      media: media,
    );
  }

  static List<KilakilaRoomSnapshot> _directoryRooms(Object? data) {
    final result = <KilakilaRoomSnapshot>[];
    final seen = <String>{};
    for (final row in _rows(data)) {
      final type = _nonnegative(row['dataType']);
      if (type != 8) continue;
      final room = _snapshot(_object(row['roomResq']), _object(row['userResp']));
      if (seen.add(room.roomId)) result.add(room);
    }
    return result;
  }

  Future<KilakilaDirectoryPage> directory({int page = 1, int pageSize = 10, int type = 0, CancelToken? cancel}) async {
    if (page < 1 || page > 100000 || pageSize < 1 || pageSize > 100 || !{0, 107}.contains(type)) {
      throw const KilakilaException(KilakilaFailure.schema);
    }
    final envelope = await _get(
      '/pcLive/timeline',
      wrapped: true,
      cancel: cancel,
      query: {'tag': '0', 'type': '$type', 'genderType': '0', 'pageNo': '$page', 'pageSize': '$pageSize'},
    );
    final body = _object(envelope['b']);
    if (_integer(body['pageNo']) != page || _integer(body['pageSize']) != pageSize || body['isLastPage'] is! bool) {
      throw const KilakilaException(KilakilaFailure.schema);
    }
    return KilakilaDirectoryPage(
      rooms: _directoryRooms(body['data']),
      page: page,
      hasMore: !(body['isLastPage'] as bool),
    );
  }

  Future<List<KilakilaRoomSnapshot>> recommendations({CancelToken? cancel}) async {
    final envelope = await _get('/pcLive/recommend', wrapped: true, cancel: cancel);
    // The real successful response can omit b entirely. Only this optional
    // showcase has this contract; a missing timeline/room body is not empty.
    return List.unmodifiable(envelope['b'] == null ? <KilakilaRoomSnapshot>[] : _directoryRooms(envelope['b']));
  }

  Future<KilakilaRoomSnapshot> detail(
    String roomId, {
    bool playback = true,
    String? expectedUserId,
    CancelToken? cancel,
  }) async {
    final requested = id(roomId);
    final owner = expectedUserId == null ? null : id(expectedUserId);
    final envelope = await _get('/LiveRoom/getRoomInfo', wrapped: false, cancel: cancel, query: {'roomId': requested});
    final room = _object(envelope['b']);
    if (_id(room['roomIdStr']) != requested || (owner != null && _id(room['uid']) != owner)) {
      throw const KilakilaException(KilakilaFailure.schema);
    }
    return _snapshot(room, _object(room['userInfo']), playback: playback);
  }
}
