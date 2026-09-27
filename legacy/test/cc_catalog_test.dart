import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/site/cc/cc_site.dart';
import 'package:pure_live/core/site/cc/cc_catalog.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/modules/areas/areas_list_controller.dart';
import 'package:hive_ce/hive.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply);
  final FutureOr<ResponseBody> Function(RequestOptions) reply;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream, Future<void>? cancel) async =>
      reply(options);
  @override
  void close({bool force = false}) {}
}

class _Controller extends AreasListController {
  _Controller() : super(Site(id: 'cc', name: 'CC', logo: '', liveSite: CCSite()));
  final errors = <Object>[];
  @override
  bool get usesDesktopPagination => true;
  @override
  Future<bool> checkNetworkBeforeRequest() async => true;
  @override
  void handleError(Object error, {bool showPageError = false}) {
    errors.add(error);
    pageError.value = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio previous;
  late Dio dio;
  late List<RequestOptions> requests;
  var status = 200;
  late Object games;
  late Object config;
  Completer<void>? gate;
  setUpAll(() async {
    await Hive.openBox<dynamic>('app_settings', bytes: Uint8List(0));
    await HivePrefUtil.init();
  });
  tearDownAll(() async => Hive.close());
  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    previous = HttpClient.instance.dio;
    requests = [];
    status = 200;
    gate = null;
    games = jsonDecode(File('test/fixtures/cc/dashen-games.json').readAsStringSync());
    config = jsonDecode(File('test/fixtures/cc/dashen-live-config.json').readAsStringSync());
    dio = Dio()
      ..httpClientAdapter = _Adapter((request) async {
        requests.add(request);
        if (request.method == 'POST' && gate != null) await gate!.future;
        return ResponseBody.fromString(
          // Preserve the old endpoint's observed HTML response for the red
          // run: failure is the empty taxonomy, not an absent test fixture.
          request.uri.host == 'cc.163.com'
              ? '<!DOCTYPE html><html>migration</html>'
              : jsonEncode(request.method == 'POST' ? config : games),
          status,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
    HttpClient.instance.dio = dio;
  });
  tearDown(() {
    HttpClient.instance.dio = previous;
    dio.close(force: true);
    Get.reset();
  });

  test('official configuration yields 20 categories plus 3 distinct room or event entries', () async {
    final groups = await CCSite().getCategores(1, 1000);
    expect(groups.expand((g) => g.children), hasLength(23));
    expect(groups.first.children, hasLength(20));
    expect(groups.last.children, hasLength(3));
    expect(groups.first.children.map((a) => a.areaId), contains('3'));
    expect(groups.last.children.map((a) => a.areaId), ['official:249133', 'official:341436398', 'official:586568']);
    expect(requests.map((r) => r.uri.host), isNot(contains('cc.163.com')));
    expect(requests.first.queryParameters, {'gameType': 'NETEASE'});
    expect(requests.last.method, 'POST');
    expect(requests.last.data, {'id': CCCatalog.configurationId});
    expect(requests.last.headers['origin'], 'https://ds.163.com');
    expect(requests.last.headers['referer'], 'https://ds.163.com/glive/');
  });

  test('catalogue transport failure is an error rather than four empty successful tabs', () async {
    status = 503;
    await expectLater(CCSite().getCategores(1, 1000), throwsA(anything));
  });

  List<dynamic> entries() => ((config as Map)['result']['itemList'] as List).single['itemList'] as List;

  test('unselected game metadata never becomes a live category and hidden entries are excluded', () {
    entries().first['hidden'] = true;
    final groups = CCCatalog.parse(games, config);
    expect(groups.expand((g) => g.children), hasLength(22));
    expect(groups.first.children, hasLength(20));
    expect(groups.last.children, hasLength(2));
  });

  test('empty and explicitly hidden live configuration are authoritative empty snapshots', () {
    entries().clear();
    expect(CCCatalog.parse(games, config), isEmpty);
    (config as Map)['result']['hidden'] = true;
    expect(CCCatalog.parse(games, config), isEmpty);
  });

  for (final route in [
    'https://example.test/123/',
    'http://cc.163.com/123/',
    'https://user@cc.163.com/123/',
    'https://cc.163.com:123/123/',
    'https://cc.163.com/123/#fragment',
    'https://cc.163.com/unrecognized/',
    'https://cc.163.com/n/ds_category/0/',
  ]) {
    test('unexpected live route is rejected atomically: $route', () {
      entries().last['content'] = route;
      expect(() => CCCatalog.parse(games, config), throwsFormatException);
    });
  }

  test('missing metadata, duplicate identity and schema drift are not partial successful catalogues', () {
    final saved = jsonEncode(config);
    entries().last['name'] = 'missing-game';
    expect(() => CCCatalog.parse(games, config), throwsFormatException);
    config = jsonDecode(saved);
    entries().add(Map.of(entries().first));
    expect(() => CCCatalog.parse(games, config), throwsFormatException);
    config = jsonDecode(saved);
    (config as Map)['result']['itemList'] = [];
    expect(() => CCCatalog.parse(games, config), throwsFormatException);
    expect(() => CCCatalog.parse(games, '<html>migration</html>'), throwsFormatException);
  });

  test('numeric game identities survive taxonomy changes while official IDs remain distinct', () {
    final groups = CCCatalog.parse(games, config);
    final game = groups.first.children.first;
    final old = LiveArea(platform: 'cc', areaId: game.areaId, areaType: '2');
    expect(old.hasSameIdentity(game), isTrue);
    final official = LiveArea.fromJson(groups.last.children.first.toJson());
    expect(CCCatalog.officialEntryUri(official)?.host, 'cc.163.com');
    expect(official.hasSameIdentity(LiveArea(platform: 'cc', areaId: '249133')), isFalse);
    expect(CCCatalog.officialEntryUri(LiveArea(platform: 'cc', areaId: 'official:../file')), isNull);
    expect(CCCatalog.officialEntryUri(LiveArea(platform: 'huya', areaId: 'official:249133')), isNull);
  });

  test('removed parent selects an available tab; failed refresh keeps old taxonomy', () async {
    final controller = _Controller();
    addTearDown(controller.onClose);
    controller.categories.assignAll([
      for (final id in ['1', '2', '4', '5']) AppLiveCategory(id: id, name: id, children: []),
    ]);
    controller.tabIndex.value = 3;
    await controller.loadData();
    expect(controller.tabIndex.value, 0);
    expect(controller.list, hasLength(20));
    controller.selectCategory(1);
    final oldRows = controller.list.toList();
    final oldGroups = controller.categories.toList();
    status = 503;
    await controller.refreshData();
    expect(controller.errors, hasLength(1));
    expect(controller.list, oldRows);
    expect(controller.categories, oldGroups);
    expect(controller.tabIndex.value, 1);
    expect(controller.showInlineError, isTrue);
    status = 200;
    await controller.retryData();
    expect(controller.tabIndex.value, 1);
    expect(controller.list, hasLength(3));
  });

  test('a tab selected during catalogue refresh remains selected after the response', () async {
    final controller = _Controller();
    addTearDown(controller.onClose);
    await controller.loadData();
    gate = Completer<void>();
    final refresh = controller.refreshData();
    for (var i = 0; i < 20 && requests.length < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(requests, hasLength(4));
    controller.selectCategory(1);
    gate!.complete();
    await refresh;
    expect(controller.tabIndex.value, 1);
    expect(controller.list, hasLength(3));
  });
}
