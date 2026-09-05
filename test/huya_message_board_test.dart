import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/huya/huya_request_params.dart';
import 'package:pure_live/core/site/huya/huya_utils.dart';
import 'package:pure_live/core/tars/game_event_message_board_info.dart';
import 'package:pure_live/core/tars/get_game_event_message_board_req.dart';
import 'package:pure_live/core/tars/get_game_event_message_board_rsp.dart';
import 'package:pure_live/pkg/tars/codec/tars_output_stream.dart';
import 'package:pure_live/pkg/tars/tup/tars_uni_packet.dart';

void main() {
  test('message-board HTTP has HTTPS and bounded connection/send/receive waits', () {
    final client = createHuyaMessageBoardClient();
    addTearDown(() => client.dio.close(force: true));
    expect(client.baseUrl, 'https://wup.huya.com');
    expect(client.servantName, 'wupui');
    expect(client.dio.options.connectTimeout, const Duration(seconds: 2));
    expect(client.dio.options.sendTimeout, const Duration(seconds: 2));
    expect(client.dio.options.receiveTimeout, const Duration(seconds: 2));
    expect(client.dio.options.headers['User-Agent'], HuyaRequestParams.hysdkUa);
  });

  for (final first in [true, false]) {
    test('empty board first=$first is safe and closes its owned HTTP client', () async {
      final adapter = _BoardAdapter()..response.complete(_boardResponse([]));
      final client = createHuyaMessageBoardClient()..dio.httpClientAdapter = adapter;
      addTearDown(() => client.dio.close(force: true));
      final result = await getHuyaSuperChatMessageList(lPid: 123, first: first, clientFactory: () => client);
      expect(result, isEmpty);
      expect(adapter.closedWithForce, isTrue);
      final packet = TarsUniPacket()..decode(Uint8List.fromList(adapter.requestBody));
      expect(packet.funcName, 'getHeadLineMessageBoard');
      final request = packet.get('tReq', GetGameEventMessageBoardReq());
      expect(request.lPid, 123);
      expect(request.iPageSize, 10);
      expect(request.tId.sHuYaUA, HuyaRequestParams.hysdkUa);
    });
  }

  for (final failure in ['HTTP failure', 'malformed WUP']) {
    test('$failure releases the owned message-board connection', () async {
      final adapter = _BoardAdapter()
        ..response.complete(ResponseBody.fromBytes([1, 2, 3], failure == 'HTTP failure' ? 503 : 200));
      final client = createHuyaMessageBoardClient()..dio.httpClientAdapter = adapter;
      addTearDown(() => client.dio.close(force: true));
      await expectLater(getHuyaSuperChatMessageList(lPid: 123, clientFactory: () => client), throwsA(anything));
      expect(adapter.closedWithForce, isTrue);
    });
  }

  test('stalled board times out and closes transport before retry can outlive it', () async {
    final adapter = _BoardAdapter();
    final client = createHuyaMessageBoardClient()..dio.httpClientAdapter = adapter;
    addTearDown(() => client.dio.close(force: true));
    final request = getHuyaSuperChatMessageList(lPid: 123, clientFactory: () => client);
    // The outer limit keeps the red test bounded; it does not close the client.
    await expectLater(request.timeout(const Duration(seconds: 4)), throwsA(isA<TimeoutException>()));
    expect(adapter.closedWithForce, isTrue, reason: 'abandoning a Future must also close its actual HTTP transport');
    expect(adapter.response.isCompleted, isTrue);
  });

  test('board preserves event IDs, filters empty/expired items and selects newest start', () async {
    GameEventMessageBoardInfo item(int id, int remaining, {String text = 'message'}) => GameEventMessageBoardInfo()
      ..lMessageId = id
      ..sContent = text
      ..iTotalSec = 60
      ..iCountDown = remaining
      ..iCostPay = 1200;
    final expired = item(4, 0)..iTotalSec = 0;
    final adapter = _BoardAdapter()
      ..response.complete(_boardResponse([item(2, 50), item(1, 10), item(3, 30, text: ' '), expired]));
    final client = createHuyaMessageBoardClient()..dio.httpClientAdapter = adapter;
    addTearDown(() => client.dio.close(force: true));
    final result = await getHuyaSuperChatMessageList(lPid: 123, clientFactory: () => client);
    expect(result, hasLength(1));
    expect(result.single.messageId, 'huya:2');
    expect(result.single.price, 12);
    expect(adapter.closedWithForce, isTrue);
  });
}

ResponseBody _boardResponse(List<GameEventMessageBoardInfo> items) {
  final response = GetGameEventMessageBoardRsp()..tMessageBoardPanel.vGameEventMessageBoardInfo = items;
  final packet = TarsUniPacket()
    ..setTarsVersion(3)
    ..servantName = 'wupui'
    ..funcName = 'getHeadLineMessageBoard'
    ..put('tRsp', response);
  // Responses use the empty key for their result code; the request-oriented
  // put() helper deliberately rejects that key, so encode the response field.
  packet.newData[''] = (TarsOutputStream()..write(0, 0)).toUint8List();
  return ResponseBody.fromBytes(packet.encode(), 200);
}

class _BoardAdapter implements HttpClientAdapter {
  final response = Completer<ResponseBody>();
  List<int> requestBody = [];
  bool closedWithForce = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestBody = await requestStream?.expand((chunk) => chunk).toList() ?? [];
    return response.future;
  }

  @override
  void close({bool force = false}) {
    closedWithForce = force;
    if (!response.isCompleted) response.completeError(StateError('fixture connection closed'));
  }
}
